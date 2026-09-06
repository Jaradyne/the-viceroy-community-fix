// The Viceroy Community Fix launcher.
// Native Windows x64 console launcher; patch logic remains in ViceroyFix.ps1.

typedef unsigned char BYTE;
typedef unsigned short WORD;
typedef unsigned int DWORD;
typedef long long LONG_PTR;
typedef void* HANDLE;
typedef void* HMODULE;
typedef void* LPVOID;
typedef const void* LPCVOID;
typedef unsigned short WCHAR;
typedef WCHAR* LPWSTR;
typedef const WCHAR* LPCWSTR;
typedef int BOOL;

#if defined(_MSC_VER)
#define WINAPI __stdcall
#else
#define WINAPI __attribute__((ms_abi))
#endif
#define DLLIMPORT __declspec(dllimport)
#define TRUE 1
#define FALSE 0
#define INFINITE 0xFFFFFFFFu
#define STD_INPUT_HANDLE  ((DWORD)-10)
#define STD_OUTPUT_HANDLE ((DWORD)-11)
#define INVALID_HANDLE_VALUE ((HANDLE)(LONG_PTR)-1)

#pragma pack(push, 8)
typedef struct _STARTUPINFOW {
    DWORD cb;
    LPWSTR lpReserved;
    LPWSTR lpDesktop;
    LPWSTR lpTitle;
    DWORD dwX;
    DWORD dwY;
    DWORD dwXSize;
    DWORD dwYSize;
    DWORD dwXCountChars;
    DWORD dwYCountChars;
    DWORD dwFillAttribute;
    DWORD dwFlags;
    WORD wShowWindow;
    WORD cbReserved2;
    BYTE* lpReserved2;
    HANDLE hStdInput;
    HANDLE hStdOutput;
    HANDLE hStdError;
} STARTUPINFOW;

typedef struct _PROCESS_INFORMATION {
    HANDLE hProcess;
    HANDLE hThread;
    DWORD dwProcessId;
    DWORD dwThreadId;
} PROCESS_INFORMATION;
#pragma pack(pop)

DLLIMPORT DWORD  WINAPI GetModuleFileNameW(HMODULE, LPWSTR, DWORD);
DLLIMPORT BOOL   WINAPI CreateProcessW(LPCWSTR, LPWSTR, LPVOID, LPVOID, BOOL, DWORD, LPVOID, LPCWSTR, STARTUPINFOW*, PROCESS_INFORMATION*);
DLLIMPORT DWORD  WINAPI WaitForSingleObject(HANDLE, DWORD);
DLLIMPORT BOOL   WINAPI GetExitCodeProcess(HANDLE, DWORD*);
DLLIMPORT BOOL   WINAPI CloseHandle(HANDLE);
DLLIMPORT HANDLE WINAPI GetStdHandle(DWORD);
DLLIMPORT BOOL   WINAPI WriteFile(HANDLE, LPCVOID, DWORD, DWORD*, LPVOID);
DLLIMPORT BOOL   WINAPI ReadFile(HANDLE, LPVOID, DWORD, DWORD*, LPVOID);
DLLIMPORT void   WINAPI ExitProcess(DWORD);
DLLIMPORT BOOL   WINAPI SetConsoleTitleW(LPCWSTR);

static WCHAR g_module_path[32768];
static WCHAR g_command[32768];
static STARTUPINFOW g_si;
static PROCESS_INFORMATION g_pi;

static BOOL append_w(WCHAR* dst, DWORD cap, DWORD* pos, const WCHAR* src) {
    while (*src) {
        if (*pos + 1 >= cap) return FALSE;
        dst[(*pos)++] = *src++;
    }
    dst[*pos] = 0;
    return TRUE;
}

static void write_ascii(const char* s) {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (!h || h == INVALID_HANDLE_VALUE) return;
    DWORD len = 0, written = 0;
    while (s[len]) ++len;
    WriteFile(h, s, len, &written, (LPVOID)0);
}

static void pause_console(void) {
    write_ascii("\r\nPress Enter to continue . . .");
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    if (!h || h == INVALID_HANDLE_VALUE) return;
    char ch;
    DWORD got = 0;
    ReadFile(h, &ch, 1, &got, (LPVOID)0);
}

void entry(void) {
    SetConsoleTitleW(L"The Viceroy Community Fix 1.0.0");

    DWORD n = GetModuleFileNameW((HMODULE)0, g_module_path, 32768);
    if (!n || n >= 32767) {
        write_ascii("Could not determine the launcher path.\r\n");
        pause_console();
        ExitProcess(1);
    }

    DWORD slash = n;
    while (slash > 0 && g_module_path[slash - 1] != L'\\' && g_module_path[slash - 1] != L'/') --slash;
    if (slash == 0) {
        write_ascii("Could not determine the launcher directory.\r\n");
        pause_console();
        ExitProcess(1);
    }
    g_module_path[slash] = 0; // directory, including trailing slash

    DWORD pos = 0;
    const WCHAR* pre = L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"";
    const WCHAR* script = L"ViceroyFix.ps1\"";
    if (!append_w(g_command, 32768, &pos, pre) ||
        !append_w(g_command, 32768, &pos, g_module_path) ||
        !append_w(g_command, 32768, &pos, script)) {
        write_ascii("Launcher path is too long.\r\n");
        pause_console();
        ExitProcess(1);
    }

    g_si.cb = (DWORD)sizeof(g_si);

    BOOL ok = CreateProcessW((LPCWSTR)0, g_command, (LPVOID)0, (LPVOID)0, TRUE, 0, (LPVOID)0,
                             g_module_path, &g_si, &g_pi);
    if (!ok) {
        write_ascii("Could not start Windows PowerShell. Make sure ViceroyFix.ps1 is beside ViceroyFix.exe.\r\n");
        pause_console();
        ExitProcess(1);
    }

    WaitForSingleObject(g_pi.hProcess, INFINITE);
    DWORD exit_code = 1;
    GetExitCodeProcess(g_pi.hProcess, &exit_code);
    CloseHandle(g_pi.hThread);
    CloseHandle(g_pi.hProcess);

    pause_console();
    ExitProcess(exit_code);
}
