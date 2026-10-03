/* Compatibility bridge for Atoll 2.3.3's dedicated Amazon/Qobuz slot.
 * Only Qobuz controls are redirected. Spotify keeps its native AppleScript.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
typedef void (*SendCommand)(int, CFTypeRef);
typedef void (*SetElapsed)(double);
typedef void (*SetMode)(int);
static SendCommand systemSend;
static SetElapsed systemSeek;
static SetMode systemShuffle, systemRepeat;

static void runDedicated(const char *action, const char *value) {
    char *args[] = {"/usr/bin/python3", "/Applications/Atoll.app/Contents/Resources/qobuz_engine.py", (char *)action, (char *)value, NULL};
    pid_t child;
    int status = posix_spawn(&child, args[0], NULL, NULL, args, environ);
    fprintf(stderr, "[QobuzControls] dedicated %s %s, spawn status %d\n", action, value, status);
    if (!status) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int result = 0;
        pid_t reaped;
        do { reaped = waitpid(child, &result, 0); } while (reaped < 0 && errno == EINTR);
        if (reaped == child && WIFEXITED(result) && WEXITSTATUS(result))
            fprintf(stderr, "[QobuzControls] %s failed with exit %d\n", action, WEXITSTATUS(result));
    });
}

static int qobuzSelected(void) {
    CFStringRef domain = CFSTR("com.Ebullioscopic.Atoll");
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("mediaController"), domain);
    int selected = value && CFGetTypeID(value) == CFStringGetTypeID() &&
        (CFEqual(value, CFSTR("Amazon Music")) || CFEqual(value, CFSTR("Qobuz")));
    if (value) CFRelease(value);
    return selected;
}

static void qobuzSend(int command, CFTypeRef options) {
    if (!qobuzSelected()) {
        if (systemSend) systemSend(command, options);
        return;
    }
    char code[16];
    snprintf(code, sizeof(code), "%d", command);
    runDedicated("send", code);
}

static void qobuzSeek(double time) {
    if (!qobuzSelected()) { if (systemSeek) systemSeek(time); return; }
    char value[64]; snprintf(value, sizeof(value), "%.6f", time);
    runDedicated("seek", value);
}
static void qobuzShuffle(int mode) {
    if (!qobuzSelected()) { if (systemShuffle) systemShuffle(mode); return; }
    char value[16]; snprintf(value, sizeof(value), "%d", mode);
    runDedicated("shuffle", value);
}
static void qobuzRepeat(int mode) {
    if (!qobuzSelected()) { if (systemRepeat) systemRepeat(mode); return; }
    char value[16]; snprintf(value, sizeof(value), "%d", mode);
    runDedicated("repeat", value);
}

static void (*dedicatedLookup(CFBundleRef bundle, CFStringRef name))(void) {
    // dyld excludes references in the interposer's own image from replacement.
    void (*function)(void) = CFBundleGetFunctionPointerForName(bundle, name);
    if (!function) return NULL;
    if (CFEqual(name, CFSTR("MRMediaRemoteSendCommand"))) {
        systemSend = (SendCommand)function;
        return (void (*)(void))qobuzSend;
    }
    if (CFEqual(name, CFSTR("MRMediaRemoteSetElapsedTime"))) {
        systemSeek = (SetElapsed)function;
        return (void (*)(void))qobuzSeek;
    }
    if (CFEqual(name, CFSTR("MRMediaRemoteSetShuffleMode"))) {
        systemShuffle = (SetMode)function;
        return (void (*)(void))qobuzShuffle;
    }
    if (CFEqual(name, CFSTR("MRMediaRemoteSetRepeatMode"))) {
        systemRepeat = (SetMode)function;
        return (void (*)(void))qobuzRepeat;
    }
    return function;
}

__attribute__((used)) static struct { const void *replacement; const void *original; }
interpose __attribute__((section("__DATA,__interpose"))) = {
    (const void *)dedicatedLookup, (const void *)CFBundleGetFunctionPointerForName
};
