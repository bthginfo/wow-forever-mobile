/* Use the bundled Wine UCRT when building with Android's LLVM and the MinGW headers. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>

int wmain(int argc, WCHAR **argv);

int vsnprintf(char *buffer, size_t size, const char *format, va_list arguments) {
    return __stdio_common_vsprintf(_CRT_INTERNAL_PRINTF_STANDARD_SNPRINTF_BEHAVIOR,
                                    buffer, size, format, NULL, arguments);
}

int snprintf(char *buffer, size_t size, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    const int length = vsnprintf(buffer, size, format, arguments);
    va_end(arguments);
    return length;
}

void mainCRTStartup(void) {
    int argc = 0;
    WCHAR **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) ExitProcess(2);
    const int status = wmain(argc, argv);
    LocalFree(argv);
    ExitProcess((UINT)status);
}
