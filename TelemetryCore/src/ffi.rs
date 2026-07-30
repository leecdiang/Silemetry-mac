// C ABI wrapper — panic-safe FFI exports
use crate::sampler::TelemetrySampler;
use crate::types::*;
use std::panic::AssertUnwindSafe;

// Helper: wrap a fallible call with panic protection
fn safe_call<F: FnOnce() -> TBErrorCode>(f: F) -> TBErrorCode {
    std::panic::catch_unwind(AssertUnwindSafe(f)).unwrap_or(TBErrorCode::Internal)
}

// ===== Create =====
#[no_mangle]
pub extern "C" fn tb_telemetry_create() -> *mut TelemetrySampler {
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
        Box::into_raw(Box::new(TelemetrySampler::new()))
    }));
    match result {
        Ok(ptr) => ptr,
        Err(_) => std::ptr::null_mut(),
    }
}

// ===== Start =====
#[no_mangle]
pub extern "C" fn tb_telemetry_start(handle: *mut TelemetrySampler, interval_ms: u32) -> TBErrorCode {
    safe_call(|| {
        if handle.is_null() { return TBErrorCode::InvalidArgument; }
        let sampler = unsafe { &mut *handle };
        match sampler.start(interval_ms) {
            Ok(()) => TBErrorCode::Ok,
            Err(e) => e,
        }
    })
}

// ===== Wait next =====
#[no_mangle]
pub extern "C" fn tb_telemetry_wait_next(
    handle: *mut TelemetrySampler,
    after_sequence_id: u64,
    timeout_ms: u32,
    out_sample: *mut TBTelemetrySample,
) -> TBErrorCode {
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || out_sample.is_null() {
            return TBErrorCode::InvalidArgument;
        }
        let sampler = unsafe { &mut *handle };
        match sampler.wait_next(after_sequence_id, timeout_ms) {
            Ok(sample) => {
                unsafe { *out_sample = sample; }
                TBErrorCode::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(TBErrorCode::Internal)
}

// ===== Capabilities =====
#[no_mangle]
pub extern "C" fn tb_telemetry_capabilities(handle: *mut TelemetrySampler) -> u64 {
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() { return 0; }
        let sampler = unsafe { &*handle };
        sampler.capabilities()
    }));
    result.unwrap_or(0)
}

// ===== Last error =====
#[no_mangle]
pub extern "C" fn tb_telemetry_last_error(
    handle: *mut TelemetrySampler,
    buffer: *mut i8,
    buffer_len: u32,
) -> TBErrorCode {
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || buffer.is_null() || buffer_len == 0 {
            return TBErrorCode::InvalidArgument;
        }
        let sampler = unsafe { &*handle };
        let err_str = sampler.last_error_string();
        let bytes = err_str.as_bytes();
        let copy_len = bytes.len().min((buffer_len - 1) as usize);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const i8, buffer, copy_len);
            *buffer.add(copy_len) = 0;
        }
        TBErrorCode::Ok
    }));
    result.unwrap_or(TBErrorCode::Internal)
}

// ===== Stop =====
#[no_mangle]
pub extern "C" fn tb_telemetry_stop(handle: *mut TelemetrySampler) -> TBErrorCode {
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() { return TBErrorCode::InvalidArgument; }
        let sampler = unsafe { &mut *handle };
        match sampler.stop() {
            Ok(()) => TBErrorCode::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(TBErrorCode::Internal)
}

// ===== Destroy =====
#[no_mangle]
pub extern "C" fn tb_telemetry_destroy(handle: *mut TelemetrySampler) {
    if handle.is_null() { return; }
    let _ = std::panic::catch_unwind(AssertUnwindSafe(|| {
        let _boxed = unsafe { Box::from_raw(handle) };
        // Drop runs here, which calls TelemetrySampler::drop() -> stop()
    }));
}

// ===== Version =====
#[no_mangle]
pub extern "C" fn tb_telemetry_core_version() -> *const i8 {
    "ThermalBenchTelemetryCore 0.1.0 (macmon 0.8.0)\0".as_ptr() as *const i8
}
