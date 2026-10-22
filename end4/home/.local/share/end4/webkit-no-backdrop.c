#define _GNU_SOURCE
#include <dlfcn.h>

/* WebKitGTK 2.54.1 can recursively repaint overlapping backdrop-filter layers.
 * Scope the user stylesheet to web views in processes launched with this shim.
 * Resolve GTK/WebKit dynamically so this does not preload a second GTK stack.
 */
void *webkit_web_view_get_settings(void *view) {
    static void *(*original)(void *);
    if (!original)
        original = dlsym(RTLD_NEXT, "webkit_web_view_get_settings");
    if (!original)
        return 0;
    void *settings = original(view);
    unsigned (*major)(void) = dlsym(RTLD_NEXT, "webkit_get_major_version");
    unsigned (*minor)(void) = dlsym(RTLD_NEXT, "webkit_get_minor_version");
    unsigned (*micro)(void) = dlsym(RTLD_NEXT, "webkit_get_micro_version");
    /* Stop applying this workaround automatically after a WebKit update. */
    if (!major || !minor || !micro || major() != 2 || minor() != 54 || micro() != 1)
        return settings;
    void *(*get_data)(void *, const char *) = dlsym(RTLD_NEXT, "g_object_get_data");
    void (*set_data)(void *, const char *, void *) = dlsym(RTLD_NEXT, "g_object_set_data");
    void *(*get_manager)(void *) = dlsym(RTLD_NEXT, "webkit_web_view_get_user_content_manager");
    void *(*new_sheet)(const char *, int, int, const char *const *, const char *const *) = dlsym(RTLD_NEXT, "webkit_user_style_sheet_new");
    void (*add_sheet)(void *, void *) = dlsym(RTLD_NEXT, "webkit_user_content_manager_add_style_sheet");
    void (*unref_sheet)(void *) = dlsym(RTLD_NEXT, "webkit_user_style_sheet_unref");
    if (!get_data || !set_data || !get_manager || !new_sheet || !add_sheet || !unref_sheet)
        return settings;
    if (get_data(view, "end4-no-backdrop"))
        return settings;
    void *manager = get_manager(view);
    if (!manager)
        return settings;
    /* INJECT_ALL_FRAMES=0 and USER_STYLE_LEVEL_USER=0 are stable public enums. */
    void *sheet = new_sheet("*, *::before, *::after { -webkit-backdrop-filter: none !important; backdrop-filter: none !important; }", 0, 0, 0, 0);
    if (sheet) {
        add_sheet(manager, sheet);
        unref_sheet(sheet);
        set_data(view, "end4-no-backdrop", (void *)1);
    }
    return settings;
}
