#include <windows.h>
#include <string.h>
#include <stdio.h>

static void escape_for_ps(const char *src, char *dst, int dst_size) {
    int j = 0;
    for (int i = 0; src[i] && j < dst_size - 2; i++) {
        if (src[i] == '\'') {
            dst[j++] = '\'';
            dst[j++] = '\'';
        } else {
            dst[j++] = src[i];
        }
    }
    dst[j] = '\0';
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    (void)hInstance; (void)hPrevInstance; (void)nCmdShow;

    if (lpCmdLine == NULL || lpCmdLine[0] == '\0') return 1;

    char title_raw[512] = {0};
    char body_raw[1024] = {0};

    char *p = lpCmdLine;
    while (*p == ' ') p++;

    /* Extract first argument (title) */
    if (*p == '"') {
        p++;
        int i = 0;
        while (*p && *p != '"' && i < (int)sizeof(title_raw) - 1) {
            title_raw[i++] = *p++;
        }
        title_raw[i] = '\0';
        if (*p == '"') p++;
    } else {
        int i = 0;
        while (*p && *p != ' ' && i < (int)sizeof(title_raw) - 1) {
            title_raw[i++] = *p++;
        }
        title_raw[i] = '\0';
    }

    while (*p == ' ') p++;

    /* Extract second argument (body) */
    if (*p == '"') {
        p++;
        int i = 0;
        while (*p && *p != '"' && i < (int)sizeof(body_raw) - 1) {
            body_raw[i++] = *p++;
        }
        body_raw[i] = '\0';
    } else if (*p) {
        int i = 0;
        while (*p && *p != ' ' && i < (int)sizeof(body_raw) - 1) {
            body_raw[i++] = *p++;
        }
        body_raw[i] = '\0';
    }

    char safe_title[1024];
    char safe_body[2048];
    escape_for_ps(title_raw, safe_title, sizeof(safe_title));
    escape_for_ps(body_raw, safe_body, sizeof(safe_body));

    /* Find icon path relative to this exe */
    char exe_path[MAX_PATH] = {0};
    GetModuleFileNameA(NULL, exe_path, MAX_PATH);
    char *last_sep = strrchr(exe_path, '\\');
    if (last_sep) *(last_sep + 1) = '\0';

    char icon_path[MAX_PATH];
    snprintf(icon_path, sizeof(icon_path), "%sdino-icon.png", exe_path);

    char safe_icon[MAX_PATH * 2];
    escape_for_ps(icon_path, safe_icon, sizeof(safe_icon));

    DWORD icon_attr = GetFileAttributesA(icon_path);
    int has_icon = (icon_attr != INVALID_FILE_ATTRIBUTES && !(icon_attr & FILE_ATTRIBUTE_DIRECTORY));

    /*
     * All paths use GetTemplateContent() + DOM manipulation only.
     * Never use LoadXml() or New-Object for WinRT types — they fail silently.
     *
     * Templates used:
     *   ToastImageAndText02 : image + 2 text fields (icon + title + body)
     *   ToastImageAndText01 : image + 1 text field  (icon + title)
     *   ToastText02         : 2 text fields          (title + body)
     *   ToastText01         : 1 text field            (title only)
     */
    char cmd[8192];
    if (safe_body[0] != '\0' && has_icon) {
        snprintf(cmd, sizeof(cmd),
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \""
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null; "
            "$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent("
                "[Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02); "
            "$img=$xml.GetElementsByTagName('image'); "
            "$img[0].SetAttribute('src','%s'); "
            "$texts=$xml.GetElementsByTagName('text'); "
            "$texts[0].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
            "$texts[1].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
            "$toast=[Windows.UI.Notifications.ToastNotification]::new($xml); "
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Dino').Show($toast);\"",
            safe_icon, safe_title, safe_body);
    } else if (safe_body[0] != '\0') {
        snprintf(cmd, sizeof(cmd),
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \""
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null; "
            "$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent("
                "[Windows.UI.Notifications.ToastTemplateType]::ToastText02); "
            "$texts=$xml.GetElementsByTagName('text'); "
            "$texts[0].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
            "$texts[1].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
            "$toast=[Windows.UI.Notifications.ToastNotification]::new($xml); "
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Dino').Show($toast);\"",
            safe_title, safe_body);
    } else if (has_icon) {
        snprintf(cmd, sizeof(cmd),
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \""
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null; "
            "$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent("
                "[Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText01); "
            "$img=$xml.GetElementsByTagName('image'); "
            "$img[0].SetAttribute('src','%s'); "
            "$xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
            "$toast=[Windows.UI.Notifications.ToastNotification]::new($xml); "
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Dino').Show($toast);\"",
            safe_icon, safe_title);
    } else {
        snprintf(cmd, sizeof(cmd),
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \""
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null; "
            "$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent("
                "[Windows.UI.Notifications.ToastTemplateType]::ToastText01); "
            "$xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('%s')) | Out-Null; "
            "$toast=[Windows.UI.Notifications.ToastNotification]::new($xml); "
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Dino').Show($toast);\"",
            safe_title);
    }

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
