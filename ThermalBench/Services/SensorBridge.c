// ThermalBench - Sensor Bridge v4 (targeted IOReport groups)
#include "SensorBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <IOKit/ps/IOPowerSources.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define DBG(fmt,...) do { struct timespec ts_; clock_gettime(CLOCK_REALTIME,&ts_); \
    fprintf(stderr,"[SENSOR_V4 %ld.%03ld] "fmt"\n",ts_.tv_sec,ts_.tv_nsec/1000000,##__VA_ARGS__); } while(0)

// ─── IOReport (loaded dynamically — private framework) ─────────────

typedef CFArrayRef  (*ioreport_copy_channels_ingroup_t)(CFStringRef);
typedef CFStringRef (*ioreport_channel_get_subgroup_t)(CFDictionaryRef);
typedef CFStringRef (*ioreport_channel_get_channelname_t)(CFDictionaryRef);
typedef CFStringRef (*ioreport_channel_get_drivername_t)(CFDictionaryRef);
typedef uint64_t    (*ioreport_channel_get_channelid_t)(CFDictionaryRef);
typedef CFDictionaryRef (*ioreport_create_subscription_t)(CFArrayRef, void*, CFDictionaryRef, CFDictionaryRef*);
typedef CFDictionaryRef (*ioreport_create_samples_t)(CFDictionaryRef, CFDictionaryRef, CFDictionaryRef*);

static ioreport_copy_channels_ingroup_t     dyn_IOReportCopyChannelsInGroup;
static ioreport_channel_get_subgroup_t      dyn_IOReportChannelGetSubGroup;
static ioreport_channel_get_channelname_t   dyn_IOReportChannelGetChannelName;
static ioreport_channel_get_drivername_t    dyn_IOReportChannelGetDriverName;
static ioreport_channel_get_channelid_t     dyn_IOReportChannelGetChannelID;
static ioreport_create_subscription_t       dyn_IOReportCreateSubscription;
static ioreport_create_samples_t            dyn_IOReportCreateSamples;

static bool resolve_ioreport(void) {
    static bool tried = false;
    static bool ok = false;
    if (tried) return ok;
    tried = true;
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY|RTLD_LOCAL);
    if (!h) { DBG("dlopen libIOReport: %s", dlerror()); return false; }
    dyn_IOReportCopyChannelsInGroup   = dlsym(h, "IOReportCopyChannelsInGroup");
    dyn_IOReportChannelGetSubGroup    = dlsym(h, "IOReportChannelGetSubGroup");
    dyn_IOReportChannelGetChannelName = dlsym(h, "IOReportChannelGetChannelName");
    dyn_IOReportChannelGetDriverName  = dlsym(h, "IOReportChannelGetDriverName");
    dyn_IOReportChannelGetChannelID   = dlsym(h, "IOReportChannelGetChannelID");
    dyn_IOReportCreateSubscription    = dlsym(h, "IOReportCreateSubscription");
    dyn_IOReportCreateSamples         = dlsym(h, "IOReportCreateSamples");
    dlclose(h);
    ok = (dyn_IOReportCopyChannelsInGroup && dyn_IOReportChannelGetSubGroup &&
          dyn_IOReportChannelGetChannelName && dyn_IOReportChannelGetChannelID &&
          dyn_IOReportCreateSubscription && dyn_IOReportCreateSamples);
    if (!ok) DBG("IOReport dlsym: not all symbols resolved");
    return ok;
}

// ─── HID temperature ──────────────────────────────────────────────

typedef struct __IOHIDEvent *IOHIDEventRef;
static IOHIDEventRef (*s_copyEvent)(void*,int64_t,int64_t,int64_t) = NULL;
static double (*s_getFloat)(void*,uint32_t) = NULL;
static bool resolve_hid(void) {
    static bool tried = false;
    static bool ok = false;
    if (tried) return ok;
    tried = true;
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOLOAD|RTLD_LAZY);
    if (!h) { DBG("dlopen IOKit: %s", dlerror()); return false; }
    s_copyEvent = dlsym(h, "IOHIDServiceClientCopyEvent");
    s_getFloat  = dlsym(h, "IOHIDEventGetFloatValue");
    dlclose(h);
    ok = (s_copyEvent != NULL && s_getFloat != NULL);
    if (!ok) DBG("HID dlsym: not all symbols resolved");
    return ok;
}
#define kIOHIDEventTypeTemperature 15

static void read_temps_hid(tb_temps_t *r) {
    if (!resolve_hid()) { DBG("No HID syms"); return; }
    IOHIDEventSystemClientRef c = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (!c) { DBG("No HID client"); return; }
    IOHIDEventSystemClientSetProperty(c, CFSTR("TemperatureSensor"), kCFBooleanTrue);
    CFArrayRef svcs = IOHIDEventSystemClientCopyServices(c);
    if (!svcs) { CFRelease(c); DBG("No HID svcs"); return; }
    CFIndex n = CFArrayGetCount(svcs);
    double ca=0,ga=0; int cn=0,gn=0;
    for (CFIndex i=0;i<n;i++) {
        void *svc = (void*)CFArrayGetValueAtIndex(svcs,i);
        if (!svc) continue;
        IOHIDEventRef e = s_copyEvent(svc, kIOHIDEventTypeTemperature, 0, 0);
        if (!e) continue;
        double t = s_getFloat(e, 0); CFRelease(e);
        if (isnan(t)||t<=0||t>=150) continue;
        CFStringRef nm = IOHIDServiceClientCopyProperty(svc, CFSTR("Product")); 
        bool gpu = false;
        if (nm) { char b[64]; CFStringGetCString(nm,b,sizeof(b),0); gpu = (strstr(b,"GPU")||strstr(b,"gpu")); CFRelease(nm); }
        if (gpu) { ga+=t; gn++; } else { ca+=t; cn++; }
    }
    CFRelease(svcs); CFRelease(c);
    if (cn) r->cpu_temp_c=ca/(double)cn;
    if (gn) r->gpu_temp_c=ga/(double)gn;
    r->soc_temp_c=fmax(r->cpu_temp_c,r->gpu_temp_c);
    if (cn+gn) r->valid=true;
}

// ─── IOReport with group-specific subscriptions ────────────────────

static void collect_channels(CFMutableArrayRef all, CFStringRef group) {
    char gname[64]={0}; if(group) CFStringGetCString(group,gname,sizeof(gname),0);
    DBG("Trying group %s...", gname);
    CFTypeRef result = dyn_IOReportCopyChannelsInGroup(group);
    if (!result) { DBG("  group returned NULL"); return; }
    CFTypeID dictID = CFDictionaryGetTypeID();
    CFTypeID resultType = CFGetTypeID(result);
    
    if (resultType == CFArrayGetTypeID()) {
        CFArrayRef arr = (CFArrayRef)result;
        CFIndex n = CFArrayGetCount(arr);
        DBG("  Array with %ld items", n);
        int good = 0;
        for (CFIndex i = 0; i < n; i++) {
            CFTypeRef val = CFArrayGetValueAtIndex(arr, i);
            if (val && CFGetTypeID(val) == dictID) { CFArrayAppendValue(all, val); good++; }
        }
        DBG("  added %d/%ld dicts", good, n);
    } else if (resultType == dictID) {
        CFDictionaryRef dict = (CFDictionaryRef)result;
        CFIndex n = CFDictionaryGetCount(dict);
        DBG("  Dictionary with %ld entries", n);
        CFTypeRef keys[n]; CFTypeRef vals[n];
        CFDictionaryGetKeysAndValues(dict, (const void**)keys, (const void**)vals);
        int good = 0;
        for (CFIndex i = 0; i < n; i++) {
            if (vals[i] && CFGetTypeID(vals[i]) == dictID) { CFArrayAppendValue(all, vals[i]); good++; }
        }
        DBG("  added %d/%ld dicts", good, n);
    } else {
        DBG("  unexpected typeID=%lu", resultType);
    }
    CFRelease(result);
}

static void read_power_ioreport(tb_power_freq_t *r) {
    if (!resolve_ioreport()) { DBG("IOReport not available"); return; }
    CFMutableArrayRef all = CFArrayCreateMutable(kCFAllocatorDefault,0,&kCFTypeArrayCallBacks);
    collect_channels(all, CFSTR("Energy Model"));
    collect_channels(all, CFSTR("CPU Stats"));
    collect_channels(all, CFSTR("GPU Stats"));
    collect_channels(all, CFSTR("Temperature"));

    if (CFArrayGetCount(all) == 0) { DBG("No channel groups found"); CFRelease(all); return; }

    DBG("Total channels to subscribe: %ld", CFArrayGetCount(all));
    CFDictionaryRef sub = NULL;
    CFDictionaryRef r2 = dyn_IOReportCreateSubscription(all, NULL, NULL, &sub);
    DBG("IOReportCreateSubscription: sub=%p r2=%p", (void*)sub, (void*)r2);
    if (!sub && !r2) { DBG("Subscription failed"); CFRelease(all); return; }

    CFDictionaryRef samples = NULL;
    CFDictionaryRef s2 = sub ? sub : r2;
    CFDictionaryRef s3 = dyn_IOReportCreateSamples(s2, NULL, &samples);
    DBG("IOReportCreateSamples: s3=%p samples=%p", (void*)s3, (void*)samples);
    if (samples) {
        r->power_valid = true;
        r->freq_valid = true;
        DBG("IOReport samples OK");
        CFRelease(samples);
    } else {
        DBG("IOReport samples returned NULL");
    }
    // A "Create" function returns a +1 reference, so the return value needs a release
    // of its own. Guard against it aliasing the out-parameter we just released.
    if (s3 && s3 != samples) CFRelease(s3);
    if (sub) CFRelease(sub);
    if (r2) CFRelease(r2);
    CFRelease(all);
}

// ─── Battery ──────────────────────────────────────────────────────

tb_battery_t tb_read_battery(void) {
    tb_battery_t r={-1,false,false};
    CFTypeRef info=IOPSCopyPowerSourcesInfo();
    if(!info) return r;
    CFArrayRef list=IOPSCopyPowerSourcesList(info);
    if(!list){CFRelease(info);return r;}
    CFIndex n=CFArrayGetCount(list);
    for(CFIndex i=0;i<n;i++){
        CFDictionaryRef ps=(CFDictionaryRef)CFArrayGetValueAtIndex(list,i);
        if(!ps)continue;
        CFStringRef src=IOPSGetProvidingPowerSourceType(ps);
        if(src){char b[32];CFStringGetCString(src,b,sizeof(b),0);r.ac_connected=!!strstr(b,"AC");r.battery_valid=true;}
        CFNumberRef cap=(CFNumberRef)CFDictionaryGetValue(ps,CFSTR("Current Capacity"));
        if(cap){int v;if(CFNumberGetValue(cap,kCFNumberSInt32Type,&v))r.battery_percent=v;}
    }
    CFRelease(list);CFRelease(info);
    return r;
}

tb_thermal_t tb_read_thermal_state(void){return(tb_thermal_t){4};}
tb_temps_t tb_read_temperatures(void){tb_temps_t r={NAN,NAN,NAN,false};read_temps_hid(&r);return r;}
tb_power_freq_t tb_read_power_frequency(void){tb_power_freq_t r={NAN,NAN,NAN,NAN,NAN,NAN,false,false};read_power_ioreport(&r);return r;}
