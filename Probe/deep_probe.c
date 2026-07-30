// Probe v4 — minimal, print-only investigation
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

typedef CFTypeRef (*io_cig_t)(CFStringRef);
static io_cig_t CIG;

static void load(void) {
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY|RTLD_LOCAL);
    if (!h) { fprintf(stderr,"IOReport: dlopen failed\n"); return; }
    CIG = dlsym(h, "IOReportCopyChannelsInGroup");
    dlclose(h);
}

static void dump_one_level(CFDictionaryRef d, int max) {
    CFIndex n = CFDictionaryGetCount(d);
    if (n > (CFIndex)max) n = max;
    CFTypeRef *keys = calloc(n, sizeof(CFTypeRef));
    CFTypeRef *vals = calloc(n, sizeof(CFTypeRef));
    if (!keys || !vals) { free(keys); free(vals); return; }
    CFDictionaryGetKeysAndValues(d, (const void**)keys, (const void**)vals);
    for (CFIndex i = 0; i < n; i++) {
        char kn[256]={0};
        CFTypeRef k = keys[i];
        if (k && CFGetTypeID(k) == CFStringGetTypeID())
            CFStringGetCString((CFStringRef)k, kn, sizeof(kn), kCFStringEncodingUTF8);
        else if (k && CFGetTypeID(k) == CFNumberGetTypeID()) {
            long long v=0; CFNumberGetValue((CFNumberRef)k, kCFNumberLongLongType, &v);
            snprintf(kn, sizeof(kn), "%lld", v);
        }
        CFTypeRef v = vals[i];
        CFTypeID vt = v ? CFGetTypeID(v) : 0;
        printf("  [%ld] key=\"%s\" vtype=%lu", i, kn, (unsigned long)vt);
        if (vt == CFNumberGetTypeID() && v) {
            long long vv = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberLongLongType, &vv);
            printf(" = %lld", vv);
        } else if (vt == CFStringGetTypeID() && v) {
            char vb[256]={0}; CFStringGetCString((CFStringRef)v, vb, sizeof(vb), kCFStringEncodingUTF8);
            printf(" = \"%s\"", vb);
        } else if (vt == CFBooleanGetTypeID() && v) {
            printf(" = %s", v == kCFBooleanTrue ? "true" : "false");
        } else if (vt == CFDictionaryGetTypeID()) {
            printf(" (dict: %ld entries)", (long)CFDictionaryGetCount((CFDictionaryRef)v));
        }
        printf("\n");
    }
    free(keys); free(vals);
}

int main(void) {
    load();
    if (!CIG) { printf("IOReport not available\n"); return 1; }

    const char *groups[] = {"Energy Model", "CPU Stats", "GPU Stats", "Temperature", NULL};
    for (const char **g = groups; *g; g++) {
        printf("=== GROUP: %s ===\n", *g);
        CFStringRef gn = CFStringCreateWithCString(kCFAllocatorDefault, *g, kCFStringEncodingUTF8);
        CFTypeRef result = CIG(gn);
        CFRelease(gn);
        if (!result) { printf("  NULL\n\n"); continue; }
        printf("  type=%lu\n", (unsigned long)CFGetTypeID(result));
        if (CFGetTypeID(result) == CFDictionaryGetTypeID()) {
            printf("  total entries: %ld\n", (long)CFDictionaryGetCount((CFDictionaryRef)result));
            dump_one_level((CFDictionaryRef)result, 20);
        }
        CFRelease(result);
        printf("\n");
    }

    // Now drill into IOReportDrivers inside CPU Stats
    printf("=== DRILL INTO: CPU Stats -> IOReportDrivers ===\n");
    CFStringRef gn = CFSTR("CPU Stats");
    CFTypeRef result = CIG(gn);
    if (result && CFGetTypeID(result) == CFDictionaryGetTypeID()) {
        CFStringRef drvKey = CFSTR("IOReportDrivers");
        CFTypeRef drivers = CFDictionaryGetValue((CFDictionaryRef)result, drvKey);
        if (drivers && CFGetTypeID(drivers) == CFDictionaryGetTypeID()) {
            printf("IOReportDrivers dict: %ld entries\n", (long)CFDictionaryGetCount((CFDictionaryRef)drivers));
            dump_one_level((CFDictionaryRef)drivers, 20);
        } else {
            printf("IOReportDrivers not found or wrong type\n");
        }
    }
    if (result) CFRelease(result);

    // HID probe
    printf("\n=== HID Temperature Services ===\n");
    void *hide = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOLOAD|RTLD_LAZY);
    if (!hide) { printf("HID dlopen failed\n"); return 0; }
    typedef void *(*h_c)(CFAllocatorRef);
    typedef CFArrayRef (*h_cs)(void*);
    typedef CFStringRef (*h_cp)(void*, CFStringRef);
    typedef void* (*h_ce)(void*, int64_t, int64_t, int64_t);
    typedef double (*h_gf)(void*, uint32_t);
    h_c create = dlsym(hide, "IOHIDEventSystemClientCreateSimpleClient");
    h_cs cs    = dlsym(hide, "IOHIDEventSystemClientCopyServices");
    h_cp cprop = dlsym(hide, "IOHIDServiceClientCopyProperty");
    h_ce ce    = dlsym(hide, "IOHIDServiceClientCopyEvent");
    h_gf gf    = dlsym(hide, "IOHIDEventGetFloatValue");
    dlclose(hide);

    if (!create || !cs || !cprop) { printf("Missing HID syms\n"); return 0; }

    void *c = create(kCFAllocatorDefault);
    if (!c) { printf("HID client NULL\n"); return 0; }
    CFArrayRef svcs = cs(c);
    if (!svcs) { printf("HID services NULL\n"); CFRelease(c); return 0; }
    CFIndex n = CFArrayGetCount(svcs);

    int temp_cnt = 0;
    double sum_cpu=0, sum_gpu=0; int n_cpu=0, n_gpu=0;
    for (CFIndex i = 0; i < n; i++) {
        void *svc = (void*)CFArrayGetValueAtIndex(svcs, i);
        CFStringRef prod = cprop(svc, CFSTR("Product"));
        char pn[256]={0};
        if (prod) { CFStringGetCString(prod, pn, sizeof(pn), kCFStringEncodingUTF8); CFRelease(prod); }

        void *ev = ce(svc, 15/*kIOHIDEventTypeTemperature*/, 0, 0);
        if (ev) {
            double t = gf(ev, 0);
            if (!isnan(t) && t > 0 && t < 150) {
                int is_gpu = (strcasestr(pn,"gpu") != NULL);
                if (is_gpu) { sum_gpu += t; n_gpu++; }
                else { sum_cpu += t; n_cpu++; }
                temp_cnt++;
                if (i < 30) printf("  [%ld] \"%s\" temp=%.1f°C\n", i, pn, t);
            }
            CFRelease(ev);
        }
    }
    printf("Total temp services: %d, CPU avg: %.1f (n=%d), GPU avg: %.1f (n=%d)\n",
           temp_cnt, n_cpu>0 ? sum_cpu/n_cpu : 0.0, n_cpu, n_gpu>0 ? sum_gpu/n_gpu : 0.0, n_gpu);

    CFRelease(svcs);
    CFRelease(c);
    printf("\n=== DONE ===\n");
    return 0;
}
