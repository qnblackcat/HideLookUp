// HideLookUp — hides "Look Up" and "New Quick Note" from the text selection
// (edit) menu on iOS 17. Verified against iOS 17.1.1 UIKitCore and WebKit.
//
// Look Up is a UICommand whose action is _define:. Each text view class below
// answers canPerformAction: for it itself, without calling up to UIResponder,
// so each one is hooked.
//
// New Quick Note only appears in web content. WKContentView's appHighlightMenu
// returns an inline menu holding one UIAction identified as
// WKActionCreateQuickNote (titled "Add to Quick Note" while a Quick Note is
// open). buildMenuForWebViewWithBuilder: skips that menu when it is nil.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

#pragma mark - Matching

static SEL HLUDefineSel;
static SEL HLULookupSel;
static NSString * const HLUQuickNoteIdentifier = @"WKActionCreateQuickNote";

static inline BOOL HLUIsLookUp(SEL action) {
    return action == HLUDefineSel || action == HLULookupSel;
}

static BOOL HLUShouldRemove(UIMenuElement *element) {
    if ([element isKindOfClass:[UICommand class]]) {
        return HLUIsLookUp(((UICommand *)element).action);
    }
    if ([element isKindOfClass:[UIAction class]]) {
        return [((UIAction *)element).identifier isEqualToString:HLUQuickNoteIdentifier];
    }
    return NO;
}

// Returns the menu without removed items, or the same instance if nothing changed.
// Submenus left empty by the filter are dropped.
static UIMenu *HLUFilterMenu(UIMenu *menu) {
    NSMutableArray<UIMenuElement *> *kept = [NSMutableArray array];
    BOOL changed = NO;

    for (UIMenuElement *element in menu.children) {
        UIMenuElement *result = element;
        if (HLUShouldRemove(element)) {
            result = nil;
        } else if ([element isKindOfClass:[UIMenu class]]) {
            UIMenu *filtered = HLUFilterMenu((UIMenu *)element);
            result = (filtered != element && filtered.children.count == 0) ? nil : filtered;
        }

        if (result != element) changed = YES;
        if (result) [kept addObject:result];
    }

    return changed ? [menu menuByReplacingChildren:kept] : menu;
}

#pragma mark - UIKit

// Plain responders and custom views.
%hook UIResponder
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return HLUIsLookUp(action) ? NO : %orig;
}
%end

// UITextView, UITextField and UISearchTextField.
%hook UITextInputController
- (BOOL)_shouldHandleResponderAction:(SEL)action {
    return HLUIsLookUp(action) ? NO : %orig;
}
%end

// Custom UITextInput views using UITextInteraction.
%hook UITextServicesInteraction
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return HLUIsLookUp(action) ? NO : %orig;
}
%end

// Last pass over the menu that is about to be shown.
%hook UIEditMenuInteraction
- (UIMenu *)_menuForSuggestedActions:(NSArray *)suggestedActions configuration:(id)configuration {
    return HLUFilterMenu(%orig);
}
%end

#pragma mark - WebKit

%group WebKit
%hook WKContentView
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return HLUIsLookUp(action) ? NO : %orig;
}

- (BOOL)canPerformActionForWebView:(SEL)action withSender:(id)sender {
    return HLUIsLookUp(action) ? NO : %orig;
}

- (UIMenu *)appHighlightMenu {
    UIMenu *menu = HLUFilterMenu(%orig);
    return menu.children.count ? menu : nil;
}
%end
%end

// WebKit may be loaded after the tweak, so hook it once it shows up.
static void HLUInitWebKit(void) {
    static BOOL initialised = NO;
    if (initialised || !objc_getClass("WKContentView")) return;
    initialised = YES;
    %init(WebKit);
}

static void HLUImageAdded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname || !strstr(info.dli_fname, "/WebKit.framework/WebKit")) return;
    // Let the ObjC runtime finish registering the image's classes first.
    dispatch_async(dispatch_get_main_queue(), ^{ HLUInitWebKit(); });
}

%ctor {
    HLUDefineSel = sel_registerName("_define:");
    HLULookupSel = sel_registerName("_lookup:");

    %init;

    // Called right away for images already loaded, then for each new one.
    _dyld_register_func_for_add_image(HLUImageAdded);
}
