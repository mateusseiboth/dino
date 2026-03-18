#include <windows.h>
#include <string.h>
#include <stdio.h>

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    (void)hInstance; (void)hPrevInstance; (void)nCmdShow;

    if (lpCmdLine == NULL || lpCmdLine[0] == '\0') return 1;

    /* Strip surrounding quotes from lpCmdLine if present */
    char title[512];
    int len = (int)strlen(lpCmdLine);
    if (len > 1 && lpCmdLine[0] == '"' && lpCmdLine[len-1] == '"') {
        len -= 2;
        if (len >= (int)sizeof(title)) len = (int)sizeof(title) - 1;
        memcpy(title, lpCmdLine + 1, len);
        title[len] = '\0';
    } else {
        strncpy(title, lpCmdLine, sizeof(title) - 1);
        title[sizeof(title) - 1] = '\0';
    }

    /* Escape single quotes for PowerShell by doubling them */
    char safe_title[1024];
    int j = 0;
    for (int i = 0; title[i] && j < (int)sizeof(safe_title) - 2; i++) {
        if (title[i] == '\'') {
            safe_title[j++] = '\'';
            safe_title[j++] = '\'';
        } else {
            safe_title[j++] = title[i];
        }
    }
    safe_title[j] = '\0';

    char cmd[4096];
    snprintf(cmd, sizeof(cmd),
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \""
        "$ErrorActionPreference='SilentlyContinue'; "
        "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null; "
        "$template=[Windows.UI.Notifications.ToastTemplateType]::ToastText01; "
        "$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template); "
        "$xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
        "$toast=[Windows.UI.Notifications.ToastNotification]::new($xml); "
        "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Dino').Show($toast);\"",
        safe_title);

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    ZeroMemory(&pi, sizeof(pi));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    BOOL ok = CreateProcessA(
        NULL, cmd, NULL, NULL, FALSE,
        CREATE_NO_WINDOW,
        NULL, NULL, &si, &pi
    );

    if (ok) {
        WaitForSingleObject(pi.hProcess, 15000);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }

    return ok ? 0 : 1;
}
