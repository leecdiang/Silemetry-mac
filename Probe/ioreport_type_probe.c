// SensorBridgeProbe — IOReport type investigation v2
#include "../ThermalBench/Services/SensorBridge.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

// Same IOReport dynamic loading as SensorBridge
typedef CFArrayRef  (*ioreport_copy_channels_ingroup_t)(CFStringRef);
typedef ioreport_copy_channels_ingroup_t (*ioreport_copy_channels_for_driver_t)(CFStringRef);
static ioreport_copy_channels_ingroup_t dyn_CopyChannelsInGroup;
static ioreport_copy_channels_for_driver_t dyn_CopyChannelsForDriver;

static void load_ioreport(void) {
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY|RTLD_LOCAL);
    if (!h) { fprintf(stderr, "ERROR: dlopen libIOReport failed: %s\n", dlerror()); return; }
    dyn_CopyChannelsInGroup = dlsym(h, "IOReportCopyChannelsInGroup");
    dyn_CopyChannelsForDriver = dlsym(h, "IOReportCopyChannelsForDriver");
    dlclose(h);
}

static void dump_dict(const char *label, CFDictionaryRef dict) {
    CFIndex n = CFDictionaryGetCount(dict);
    printf("  %s: %ld entries\n", label, n);
    if (n == 0) return;

    CFTypeRef keys[n], vals[n];
    CFDictionaryGetKeysAndValues(dict, (const void**)keys, (const void**)vals);
    for (CFIndex i = 0; i < n; i++) {
        CFTypeID kt = CFGetTypeID(keys[i]);
        CFTypeID vt = CFGetTypeID(vals[i]);

        // Key type
        char kname[64] = {0};
        if (CFGetTypeID(keys[i]) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)keys[i], kname, sizeof(kname), kCFStringEncodingUTF8);
        } else if (CFGetTypeID(keys[i]) == CFNumberGetTypeID()) {
            long long v = 0; CFNumberGetValue((CFNumberRef)keys[i], kCFNumberLongLongType, &v);
            snprintf(kname, sizeof(kname), "%lld", v);
        }

        // Value type
        const char *vtype = "?";
        if (vt == CFDictionaryGetTypeID()) vtype = "CFDictionary";
        else if (vt == CFNumberGetTypeID()) vtype = "CFNumber";
        else if (vt == CFStringGetTypeID()) vtype = "CFString";
        else if (vt == CFBooleanGetTypeID()) vtype = "CFBoolean";
        else if (vt == CFArrayGetTypeID()) vtype = "CFArray";

        printf("    [%ld] key=%s (type=%lu) val_type=%s (type=%lu)\n",
               i, kname, (unsigned long)kt, vtype, (unsigned long)vt);

        // If value is CFDictionary, try to get channel name
        if (vt == CFDictionaryGetTypeID()) {
            // Try known IOReport functions
            typedef CFStringRef (*get_name_t)(CFDictionaryRef);
            typedef uint64_t (*get_id_t)(CFDictionaryRef);
            typedef CFStringRef (*get_sub_t)(CFDictionaryRef);

            get_name_t fn_name = dlsym(RTLD_DEFAULT, "IOReportChannelGetChannelName");
            get_id_t   fn_id   = dlsym(RTLD_DEFAULT, "IOReportChannelGetChannelID");
            get_sub_t  fn_sub  = dlsym(RTLD_DEFAULT, "IOReportChannelGetSubGroup");

            if (fn_name) {
                CFStringRef nm = fn_name((CFDictionaryRef)vals[i]);
                if (nm) {
                    char nb[128] = {0};
                    CFStringGetCString(nm, nb, sizeof(nb), kCFStringEncodingUTF8);
                    printf("      ChannelName=%s\n", nb);
                }
            }
            if (fn_id) {
                uint64_t cid = fn_id((CFDictionaryRef)vals[i]);
                printf("      ChannelID=%llu\n", cid);
            }
            if (fn_sub) {
                CFStringRef sg = fn_sub((CFDictionaryRef)vals[i]);
                if (sg) {
                    char sb[128] = {0};
                    CFStringGetCString(sg, sb, sizeof(sb), kCFStringEncodingUTF8);
                    printf("      SubGroup=%s\n", sb);
                }
            }
        }
    }
}

static void probe_group(const char *gname) {
    printf("=== GROUP: %s ===\n", gname);
    CFTypeRef result = dyn_CopyChannelsInGroup(CFStringCreateWithCString(kCFAllocatorDefault, gname, kCFStringEncodingUTF8));
    if (!result) { printf("  NULL\n"); return; }
    CFTypeID tid = CFGetTypeID(result);
    printf("  type: %s (%lu)\n",
           tid == CFDictionaryGetTypeID() ? "CFDictionary" :
           tid == CFArrayGetTypeID() ? "CFArray" : "OTHER", (unsigned long)tid);

    if (tid == CFDictionaryGetTypeID()) {
        dump_dict("channels", (CFDictionaryRef)result);
    } else if (tid == CFArrayGetTypeID()) {
        printf("  Array not expected, dumping...\n");
        CFArrayRef arr = (CFArrayRef)result;
        for (CFIndex i = 0; i < CFArrayGetCount(arr); i++) {
            CFTypeRef v = CFArrayGetValueAtIndex(arr, i);
            printf("  [%ld] type=%lu\n", i, (unsigned long)CFGetTypeID(v));
        }
    }
    CFRelease(result);
}

int main(void) {
    load_ioreport();
    if (!dyn_CopyChannelsInGroup) { printf("IOReport not loaded\n"); return 1; }

    const char *groups[] = {
        "Energy Model", "CPU Stats", "GPU Stats", "Temperature",
        NULL
    };
    for (const char **g = groups; *g; g++) {
        probe_group(*g);
        printf("\n");
    }

    // Now try reading temps via HID
    printf("=== HID Temperature ===\n");
    tb_temps_t temps = tb_read_temperatures();
    printf("  valid=%d cpu=%.4f gpu=%.4f soc=%.4f\n",
           (int)temps.valid, temps.cpu_temp_c, temps.gpu_temp_c, temps.soc_temp_c);

    printf("\n=== DONE ===\n");
    return 0;
}
