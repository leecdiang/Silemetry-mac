// Background sampler thread — macmon Sampler is !Send, created per-thread
use crate::types::*;
use macmon::Sampler;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const QUEUE_CAPACITY: usize = 256;

pub struct TelemetrySampler {
    queue: Arc<Mutex<Vec<TBTelemetrySample>>>,
    running: Arc<AtomicBool>,
    stop_flag: Arc<AtomicBool>,
    last_error: Arc<Mutex<Option<String>>>,
    /// Behind a Mutex so every method can take `&self`. The C ABI hands out a raw
    /// pointer that callers may use from several threads at once; if any entry point
    /// needed `&mut self`, two concurrent calls would alias a mutable reference,
    /// which is undefined behaviour even when the operations look harmless.
    thread: Mutex<Option<thread::JoinHandle<()>>>,
}

impl TelemetrySampler {
    pub fn new() -> Self {
        TelemetrySampler {
            queue: Arc::new(Mutex::new(Vec::with_capacity(QUEUE_CAPACITY))),
            running: Arc::new(AtomicBool::new(false)),
            stop_flag: Arc::new(AtomicBool::new(false)),
            last_error: Arc::new(Mutex::new(None)),
            thread: Mutex::new(None),
        }
    }

    pub fn start(&self, interval_ms: u32) -> Result<(), TBErrorCode> {
        // Hold the thread slot for the whole call so two concurrent starts cannot
        // both pass the `running` check and spawn a sampler each.
        let mut slot = self.thread.lock().unwrap_or_else(|e| e.into_inner());

        if self.running.load(Ordering::Acquire) || slot.is_some() {
            return Err(TBErrorCode::AlreadyStarted);
        }

        let queue = Arc::clone(&self.queue);
        let running = Arc::clone(&self.running);
        let stop_flag = Arc::clone(&self.stop_flag);
        let last_error = Arc::clone(&self.last_error);

        stop_flag.store(false, Ordering::Release);
        queue.lock().unwrap_or_else(|e| e.into_inner()).clear();

        let handle = thread::Builder::new()
            .name("ThermalBench-Telemetry".into())
            .spawn(move || {
                // Create sampler INSIDE this thread
                let mut sampler = match Sampler::new() {
                    Ok(s) => s,
                    Err(e) => {
                        *last_error.lock().unwrap_or_else(|e| e.into_inner()) =
                            Some(format!("Sampler::new: {:?}", e));
                        running.store(false, Ordering::Release);
                        return;
                    }
                };

                running.store(true, Ordering::Release);
                // Start at 1: the Swift side tracks lastSeq = 0 initially and
                // wait_next only returns sequence_id > after_sequence_id, so a
                // 0-based first sample would be skipped forever.
                let mut seq: u64 = 1;

                while !stop_flag.load(Ordering::Acquire) {
                    match sampler.get_metrics(interval_ms.max(100)) {
                        Ok(metrics) => {
                            // A clock set before 1970 would make this fail; report 0
                            // rather than panicking inside the sampler thread.
                            let unix_ns = SystemTime::now()
                                .duration_since(UNIX_EPOCH)
                                .map(|d| d.as_nanos() as i64)
                                .unwrap_or(0);

                            // Per-metric validity: only advertise channels that
                            // are actually present and sane this sample. Swift
                            // decides Optional fields from available_mask, so a
                            // 0 / NaN / placeholder value must never be exposed
                            // as real data.
                            let mut mask: u64 = 0;
                            let t = &metrics.temp;
                            let sane_temp = |v: f32| v.is_finite() && v > -50.0 && v < 150.0;
                            if t.cpu_sensor_count > 0 && sane_temp(t.cpu_temp_avg) { mask |= TB_AVAIL_CPU_TEMP; }
                            if t.cpu_sensor_count > 0 && sane_temp(t.cpu_temp_max) { mask |= TB_AVAIL_CPU_TEMP_HOTTEST; }
                            if t.gpu_sensor_count > 0 && sane_temp(t.gpu_temp_avg) { mask |= TB_AVAIL_GPU_TEMP; }
                            if t.gpu_sensor_count > 0 && sane_temp(t.gpu_temp_max) { mask |= TB_AVAIL_GPU_TEMP_HOTTEST; }
                            if t.cpu_sensor_count > 0 { mask |= TB_AVAIL_CPU_SENSOR_COUNT; }
                            if t.gpu_sensor_count > 0 { mask |= TB_AVAIL_GPU_SENSOR_COUNT; }
                            if metrics.cpu_power.is_finite() && metrics.cpu_power >= 0.0 { mask |= TB_AVAIL_CPU_POWER; }
                            if metrics.gpu_power.is_finite() && metrics.gpu_power >= 0.0 { mask |= TB_AVAIL_GPU_POWER; }
                            if metrics.ane_power.is_finite() && metrics.ane_power >= 0.0 { mask |= TB_AVAIL_ANE_POWER; }
                            if metrics.ram_power.is_finite() && metrics.ram_power >= 0.0 { mask |= TB_AVAIL_DRAM_POWER; }
                            if metrics.all_power.is_finite() && metrics.all_power >= 0.0 { mask |= TB_AVAIL_PACKAGE_POWER; }
                            if metrics.pcpu_freq_mhz > 0 { mask |= TB_AVAIL_P_FREQ; }
                            if metrics.ecpu_freq_mhz > 0 { mask |= TB_AVAIL_E_FREQ; }
                            let sane_usage = |v: f32| v.is_finite() && (0.0..=1.0).contains(&v);
                            if sane_usage(metrics.pcpu_usage_ratio) { mask |= TB_AVAIL_P_USAGE; }
                            if sane_usage(metrics.ecpu_usage_ratio) { mask |= TB_AVAIL_E_USAGE; }
                            if sane_usage(metrics.cpu_usage_ratio) { mask |= TB_AVAIL_CPU_USAGE; }
                            if sane_usage(metrics.gpu_usage_ratio) { mask |= TB_AVAIL_GPU_USAGE; }

                            let sample = TBTelemetrySample {
                                sequence_id: seq,
                                monotonic_timestamp_ns: 0,
                                wall_clock_unix_ns: unix_ns,

                                cpu_temperature_avg_c: metrics.temp.cpu_temp_avg as f64,
                                cpu_temperature_hottest_c: metrics.temp.cpu_temp_max as f64,
                                gpu_temperature_avg_c: metrics.temp.gpu_temp_avg as f64,
                                gpu_temperature_hottest_c: metrics.temp.gpu_temp_max as f64,
                                cpu_temperature_sensor_count: metrics.temp.cpu_sensor_count as u32,
                                gpu_temperature_sensor_count: metrics.temp.gpu_sensor_count as u32,
                                _reserved1: 0,

                                cpu_power_w: metrics.cpu_power as f64,
                                gpu_power_w: metrics.gpu_power as f64,
                                ane_power_w: metrics.ane_power as f64,
                                dram_power_w: metrics.ram_power as f64,
                                package_power_w: metrics.all_power as f64,

                                p_cluster_frequency_mhz: metrics.pcpu_freq_mhz as f64,
                                e_cluster_frequency_mhz: metrics.ecpu_freq_mhz as f64,

                                p_cluster_utilization_ratio: metrics.pcpu_usage_ratio as f64,
                                e_cluster_utilization_ratio: metrics.ecpu_usage_ratio as f64,
                                cpu_utilization_ratio: metrics.cpu_usage_ratio as f64,
                                gpu_utilization_ratio: metrics.gpu_usage_ratio as f64,

                                // (mask computed above — per-metric validity)
                                available_mask: mask,
                                valid_mask: mask,
                                derived_mask: 0,
                                warning_mask: 0,
                            };

                            seq += 1;

                            let mut q = queue.lock().unwrap_or_else(|e| e.into_inner());
                            if q.len() >= QUEUE_CAPACITY {
                                q.remove(0);
                            }
                            q.push(sample);
                        }
                        Err(e) => {
                            *last_error.lock().unwrap_or_else(|e| e.into_inner()) =
                                Some(format!("get_metrics: {:?}", e));
                            thread::sleep(Duration::from_millis(100));
                        }
                    }
                }
                running.store(false, Ordering::Release);
                // Sampler drops here, cleaning up IOKit handles
            });

        match handle {
            Ok(h) => {
                *slot = Some(h);
                Ok(())
            }
            Err(e) => {
                *self.last_error.lock().unwrap_or_else(|e| e.into_inner()) =
                    Some(format!("spawn: {}", e));
                Err(TBErrorCode::Internal)
            }
        }
    }

    pub fn wait_next(
        &self,
        after_sequence_id: u64,
        timeout_ms: u32,
    ) -> Result<TBTelemetrySample, TBErrorCode> {
        if !self.running.load(Ordering::Acquire) {
            return Err(TBErrorCode::NotStarted);
        }

        let start = std::time::Instant::now();
        loop {
            {
                let q = self.queue.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(last) = q.last() {
                    if last.sequence_id > after_sequence_id {
                        return Ok(*last);
                    }
                }
            }

            if !self.running.load(Ordering::Acquire) {
                let q = self.queue.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(last) = q.last() {
                    if last.sequence_id > after_sequence_id {
                        return Ok(*last);
                    }
                }
                return Err(TBErrorCode::Stopped);
            }

            if timeout_ms > 0 && start.elapsed().as_millis() as u32 >= timeout_ms {
                return Err(TBErrorCode::Timeout);
            }

            thread::sleep(Duration::from_millis(10));
        }
    }

    pub fn capabilities(&self) -> u64 {
        TB_AVAIL_CPU_TEMP
            | TB_AVAIL_GPU_TEMP
            | TB_AVAIL_CPU_POWER
            | TB_AVAIL_GPU_POWER
            | TB_AVAIL_ANE_POWER
            | TB_AVAIL_DRAM_POWER
            | TB_AVAIL_PACKAGE_POWER
            | TB_AVAIL_P_FREQ
            | TB_AVAIL_E_FREQ
            | TB_AVAIL_P_USAGE
            | TB_AVAIL_E_USAGE
            | TB_AVAIL_CPU_USAGE
            | TB_AVAIL_GPU_USAGE
            | TB_AVAIL_CPU_TEMP_HOTTEST
            | TB_AVAIL_GPU_TEMP_HOTTEST
            | TB_AVAIL_CPU_SENSOR_COUNT
            | TB_AVAIL_GPU_SENSOR_COUNT
    }

    pub fn last_error_string(&self) -> String {
        self.last_error
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .unwrap_or_default()
    }

    pub fn stop(&self) -> Result<(), TBErrorCode> {
        self.stop_flag.store(true, Ordering::Release);

        // Take the handle out before joining so a second concurrent stop() sees None
        // and returns immediately instead of trying to join the same thread twice.
        let handle = self
            .thread
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(handle) = handle {
            let _ = handle.join();
        }

        self.running.store(false, Ordering::Release);
        self.queue.lock().unwrap_or_else(|e| e.into_inner()).clear();
        Ok(())
    }
}

impl Default for TelemetrySampler {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for TelemetrySampler {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}
