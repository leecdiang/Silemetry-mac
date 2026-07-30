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
    thread: Option<thread::JoinHandle<()>>,
}

impl TelemetrySampler {
    pub fn new() -> Self {
        TelemetrySampler {
            queue: Arc::new(Mutex::new(Vec::with_capacity(QUEUE_CAPACITY))),
            running: Arc::new(AtomicBool::new(false)),
            stop_flag: Arc::new(AtomicBool::new(false)),
            last_error: Arc::new(Mutex::new(None)),
            thread: None,
        }
    }

    pub fn start(&mut self, interval_ms: u32) -> Result<(), TBErrorCode> {
        if self.running.load(Ordering::Acquire) {
            return Err(TBErrorCode::AlreadyStarted);
        }

        let queue = Arc::clone(&self.queue);
        let running = Arc::clone(&self.running);
        let stop_flag = Arc::clone(&self.stop_flag);
        let last_error = Arc::clone(&self.last_error);

        stop_flag.store(false, Ordering::Release);
        queue.lock().unwrap().clear();

        let handle = thread::Builder::new()
            .name("ThermalBench-Telemetry".into())
            .spawn(move || {
                // Create sampler INSIDE this thread
                let mut sampler = match Sampler::new() {
                    Ok(s) => s,
                    Err(e) => {
                        *last_error.lock().unwrap() =
                            Some(format!("Sampler::new: {:?}", e));
                        running.store(false, Ordering::Release);
                        return;
                    }
                };

                running.store(true, Ordering::Release);
                let mut seq: u64 = 0;

                while !stop_flag.load(Ordering::Acquire) {
                    match sampler.get_metrics(interval_ms.max(100)) {
                        Ok(metrics) => {
                            let now = SystemTime::now();
                            let unix_ns =
                                now.duration_since(UNIX_EPOCH).unwrap().as_nanos() as i64;

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

                                available_mask: TB_AVAIL_CPU_TEMP
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
                                    | TB_AVAIL_GPU_SENSOR_COUNT,
                                valid_mask: !0,
                                derived_mask: 0,
                                warning_mask: 0,
                            };

                            seq += 1;

                            let mut q = queue.lock().unwrap();
                            if q.len() >= QUEUE_CAPACITY {
                                q.remove(0);
                            }
                            q.push(sample);
                        }
                        Err(e) => {
                            *last_error.lock().unwrap() =
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
                self.thread = Some(h);
                Ok(())
            }
            Err(e) => {
                *self.last_error.lock().unwrap() = Some(format!("spawn: {}", e));
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
                let q = self.queue.lock().unwrap();
                if let Some(last) = q.last() {
                    if last.sequence_id > after_sequence_id {
                        return Ok(*last);
                    }
                }
            }

            if !self.running.load(Ordering::Acquire) {
                let q = self.queue.lock().unwrap();
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
        self.last_error.lock().unwrap().clone().unwrap_or_default()
    }

    pub fn stop(&mut self) -> Result<(), TBErrorCode> {
        self.stop_flag.store(true, Ordering::Release);
        if let Some(handle) = self.thread.take() {
            let _ = handle.join();
        }
        self.running.store(false, Ordering::Release);
        self.queue.lock().unwrap().clear();
        Ok(())
    }
}

impl Drop for TelemetrySampler {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}
