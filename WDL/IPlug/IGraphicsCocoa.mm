#include "IGraphicsCocoa.h"

//forward declare this if compiling with 10.6 sdk
#if !defined(MAC_OS_X_VERSION_10_7) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_7
@interface NSScreen (LionSDK)
- (CGFloat)backingScaleFactor;
@end
#endif // MAC_OS_X_VERSION_10_7

@implementation IGRAPHICS_MENU_RCVR

- (NSMenuItem*)MenuItem
{
  return nsMenuItem;
}

- (void)OnMenuSelection:(id)sender
{
  nsMenuItem = sender;
}

@end

@implementation IGRAPHICS_NSMENU

- (id)initWithIPopupMenuAndReciever:(IPopupMenu*)pMenu : (NSView*)pView
{
  [self initWithTitle: @""];

  NSMenuItem* nsMenuItem;
  NSMutableString* nsMenuItemTitle;

  [self setAutoenablesItems:NO];

  int numItems = pMenu->GetNItems();

  for (int i = 0; i < numItems; ++i)
  {
    IPopupMenuItem* menuItem = pMenu->GetItem(i);

    nsMenuItemTitle = [[[NSMutableString alloc] initWithCString:menuItem->GetText() encoding:NSUTF8StringEncoding] autorelease];

    if (pMenu->GetPrefix())
    {
      NSString* prefixString = 0;

      switch (pMenu->GetPrefix())
      {
        case 0: prefixString = [NSString stringWithUTF8String:""]; break;
        case 1: prefixString = [NSString stringWithFormat:@"%1d: ", i+1]; break;
        case 2: prefixString = [NSString stringWithFormat:@"%02d: ", i+1]; break;
        case 3: prefixString = [NSString stringWithFormat:@"%03d: ", i+1]; break;
      }

      [nsMenuItemTitle insertString:prefixString atIndex:0];
    }

    if (menuItem->GetSubmenu())
    {
      nsMenuItem = [self addItemWithTitle:nsMenuItemTitle action:nil keyEquivalent:@""];
      NSMenu* subMenu = [[IGRAPHICS_NSMENU alloc] initWithIPopupMenuAndReciever:menuItem->GetSubmenu() :pView];
      [self setSubmenu: subMenu forItem:nsMenuItem];
      [subMenu release];
    }
    else if (menuItem->GetIsSeparator())
    {
      [self addItem:[NSMenuItem separatorItem]];
    }
    else
    {
      nsMenuItem = [self addItemWithTitle:nsMenuItemTitle action:@selector(OnMenuSelection:) keyEquivalent:@""];

      if (menuItem->GetIsTitle ())
      {
        [nsMenuItem setIndentationLevel:1];
      }

      if (menuItem->GetChecked())
      {
        [nsMenuItem setState:NSOnState];
      }
      else
      {
        [nsMenuItem setState:NSOffState];
      }
      
      if (menuItem->GetEnabled())
      {
        [nsMenuItem setEnabled:YES];
      }
      else
      {
        [nsMenuItem setEnabled:NO];
      }

    }
  }

  mIPopupMenu = pMenu;

  return self;
}

- (IPopupMenu*)AssociatedIPopupMenu
{
  return mIPopupMenu;
}

@end


NSString* ToNSString(const char* cStr)
{
  return [NSString stringWithCString:cStr encoding:NSUTF8StringEncoding];
}

inline IMouseMod GetMouseMod(NSEvent* pEvent)
{
  int mods = [pEvent modifierFlags];
  return IMouseMod(true, (mods & NSCommandKeyMask), (mods & NSShiftKeyMask), (mods & NSControlKeyMask), (mods & NSAlternateKeyMask));
}

inline IMouseMod GetRightMouseMod(NSEvent* pEvent)
{
  int mods = [pEvent modifierFlags];
  return IMouseMod(false, true, (mods & NSShiftKeyMask), (mods & NSControlKeyMask), (mods & NSAlternateKeyMask));
}

@implementation COCOA_FORMATTER
- (void) dealloc
{
  [filterCharacterSet release];
  [super dealloc];
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error
{
  if (filterCharacterSet != nil)
  {
    int i = 0;
    int len = [partialString length];
    
    for (i = 0; i < len; i++)
    {
      if (![filterCharacterSet characterIsMember:[partialString characterAtIndex:i]])
      {
        return NO;
      }
    }
  }

  if (maxLength)
  {
    if ([partialString length] > maxLength)
    {
      return NO;
    }
  }

  if (maxValue && [partialString intValue] > maxValue)
  {
    return NO;
  }

  return YES;
}

- (void) setAcceptableCharacterSet:(NSCharacterSet *) inCharacterSet
{
  [inCharacterSet retain];
  [filterCharacterSet release];
  filterCharacterSet = inCharacterSet;
}

- (void) setMaximumLength:(int) inLength
{
  maxLength = inLength;
}

- (void) setMaximumValue:(int) inValue
{
  maxValue = inValue;
}

- (NSString *)stringForObjectValue:(id)anObject
{
  if ([anObject isKindOfClass:[NSString class]])
  {
    return anObject;
  }

  return nil;
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error
{
  if (anObject && string)
  {
    *anObject = [NSString stringWithString:string];
  }

  return YES;
}
@end

inline int GetMouseOver(IGraphicsMac* pGraphics)
{
	return pGraphics->GetMouseOver();
}

@implementation IGRAPHICS_COCOA

- (id) init
{
  TRACE;

  mGraphics = 0;
  mTimer = 0;
  mPrevX = 0;
  mPrevY = 0;
  return self;
}

- (BOOL) isFlipped
{
  return mGraphics ? mGraphics->UsesNativeControls() : false;
}

- (id) initWithIGraphics: (IGraphicsMac*) pGraphics
{
  TRACE;

  mGraphics = pGraphics;
  NSRect r;
  r.origin.x = r.origin.y = 0.0f;
  r.size.width = (float) pGraphics->Width();
  r.size.height = (float) pGraphics->Height();
  self = [super initWithFrame:r];

  double sec = 1.0 / (double) pGraphics->FPS();
  mTimer = [NSTimer timerWithTimeInterval:sec target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
  [[NSRunLoop currentRunLoop] addTimer: mTimer forMode: (NSString*) kCFRunLoopCommonModes];

  // Add support for file drag'n'drop
  [self registerForDraggedTypes:[NSArray arrayWithObjects: NSFilenamesPboardType, nil]];

  return self;
}

- (BOOL) isOpaque
{
  return mGraphics ? YES : NO;
}

- (BOOL) acceptsFirstResponder
{
  return YES;
}

- (BOOL) acceptsFirstMouse: (NSEvent*) pEvent
{
  return YES;
}

- (void) viewDidMoveToWindow
{
  NSWindow* pWindow = [self window];
  if (pWindow)
  {
    [pWindow makeFirstResponder: self];
    [pWindow setAcceptsMouseMovedEvents: YES];
  }
}

- (void) drawRect: (NSRect) rect
{
  if (mGraphics)
  {
    IRECT tmpRect = ToIRECT(mGraphics, &rect);
    mGraphics->Draw(&tmpRect);
  }
}

- (void) onTimer: (NSTimer*) pTimer
{
  IRECT r;
  if (pTimer == mTimer && mGraphics && mGraphics->IsDirty(&r))
  {
    [self setNeedsDisplayInRect:ToNSRect(mGraphics, &r)];
  }
}


- (NSDragOperation)draggingEntered: (id <NSDraggingInfo>) sender {
    NSPasteboard *pboard = [sender draggingPasteboard];

    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        return NSDragOperationGeneric;
    } else {
        return NSDragOperationNone;
    }
}

- (BOOL)performDragOperation: (id<NSDraggingInfo>) sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        NSString *firstFile = [files firstObject];
        const char *firstFileCString = [firstFile UTF8String];
        NSPoint point = [sender draggingLocation];
        NSPoint relativePoint = [self convertPoint: point fromView:nil];
        int x = (int) relativePoint.x - 2;
        int y = mGraphics->Height() - (int) relativePoint.y - 3;
        mGraphics->OnFileDropped(firstFileCString, x, y);
    }
    
    return YES;
}

- (void) getMouseXY: (NSEvent*) pEvent x: (int*) pX y: (int*) pY
{
  if (mGraphics)
  {
    NSPoint pt = [self convertPoint:[pEvent locationInWindow] fromView:nil];
    *pX = (int) pt.x - 2;
    *pY = mGraphics->Height() - (int) pt.y - 3;
    mPrevX = *pX;
    mPrevY = *pY;
  }
}

- (void) mouseDown: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetMouseMod(pEvent);

    #ifdef RTAS_API
    if (ms.L && ms.R && ms.C && (mGraphics->GetParamIdxForPTAutomation(x, y) > -1))
    {
      WindowRef carbonParent = (WindowRef) [[[self window] parentWindow] windowRef];
      EventRef carbonEvent = (EventRef) [pEvent eventRef];
      SendEventToWindow(carbonEvent, carbonParent);
      return;
    }
    #endif

    if ([pEvent clickCount] > 1)
    {
      mGraphics->OnMouseDblClick(x, y, &ms);
    }
    else
    {
      mGraphics->OnMouseDown(x, y, &ms);
    }
  }
}

- (void) mouseUp: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetMouseMod(pEvent);
    mGraphics->OnMouseUp(x, y, &ms);
    
    // Tooltips could have changed
    mGraphics->UpdateTooltips();
  }
}

- (void) mouseDragged: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetMouseMod(pEvent);

    if(!mTextFieldView)
    {
      mGraphics->OnMouseDrag(x, y, &ms);
    }
  }
}

- (void) rightMouseDown: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetRightMouseMod(pEvent);
    mGraphics->OnMouseDown(x, y, &ms);
  }
}

- (void) rightMouseUp: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetRightMouseMod(pEvent);
    mGraphics->OnMouseUp(x, y, &ms);
  }
}

- (void) rightMouseDragged: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetRightMouseMod(pEvent);

    if(!mTextFieldView)
    {
      mGraphics->OnMouseDrag(x, y, &ms);
    }
  }
}

- (void) mouseMoved: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    IMouseMod ms = GetMouseMod(pEvent);
    mGraphics->OnMouseOver(x, y, &ms);
  }
}

- (void)keyDown: (NSEvent *)pEvent
{
  NSString *s = [pEvent charactersIgnoringModifiers];

  if ([s length] == 1)
  {
    int flags;
    int key = SWELL_MacKeyToWindowsKey(pEvent, &flags);
    
    // can't use getMouseXY because its a key event
    bool handle = mGraphics->OnKeyDown(mPrevX, mPrevY, key, flags);

    if (!handle)
    {
      #ifdef RTAS_API
      [[NSApp mainWindow] makeKeyWindow];
      [NSApp postEvent: [NSApp currentEvent] atStart: YES];
      #else
      // Search DAW window (works at least for REAPER)
      NSWindow* dawWindow = NULL;
      for (NSWindow* window in [NSApp windows]) {
        if ([window level] == 0 && [window frame].size.width > 0 && [window frame].size.height > 0) {
          dawWindow = window;
          break;
        }
      }
      // Bring focus to DAW window and forward the keyDown evnt to it.
      // Plugin loses focus then but it seems it can't be avoided on Mac.
      if (dawWindow != NULL) {
        [dawWindow makeKeyWindow];
        [dawWindow postEvent: [NSApp currentEvent] atStart: YES];
      }
      #endif
    }
  }
}

- (void) scrollWheel: (NSEvent*) pEvent
{
  if (mGraphics)
  {
    if(mTextFieldView) [self endUserInput ];

    int x, y;
    [self getMouseXY:pEvent x:&x y:&y];
    int d = [pEvent deltaY];

    IMouseMod ms = GetMouseMod(pEvent);
    mGraphics->OnMouseWheel(x, y, &ms, d);
  }
}

- (void) killTimer
{
  [mTimer invalidate];
  mTimer = 0;
}

- (void) removeFromSuperview
{
  if (mTextFieldView) [self endUserInput ];

  if (mGraphics)
  {
    IGraphics* graphics = mGraphics;
    mGraphics = 0;
    graphics->CloseWindow();
  }
  [super removeFromSuperview];
}

- (void) controlTextDidEndEditing: (NSNotification*) aNotification
{
  char* txt = (char*)[[mTextFieldView stringValue] UTF8String];

  if (mEdParam)
  {
    mGraphics->SetFromStringAfterPrompt(mEdControl, mEdParam, txt);
  }
  else
  {
    mEdControl->TextFromTextEntry(txt);
  }
  
  [self endUserInput ];
  [self setNeedsDisplay: YES];
}

- (IPopupMenu*) createIPopupMenu: (IPopupMenu*) pMenu : (NSRect) rect;
{
  IGRAPHICS_MENU_RCVR* dummyView = [[[IGRAPHICS_MENU_RCVR alloc] initWithFrame:rect] autorelease];
  NSMenu* nsMenu = [[[IGRAPHICS_NSMENU alloc] initWithIPopupMenuAndReciever:pMenu :dummyView] autorelease];

  NSWindow* pWindow = [self window];

  NSPoint wp = {rect.origin.x, rect.origin.y - 4};
  wp = [self convertPointToBase:wp];
  
  //fix position for retina display
  float displayScale = 1.0f;
  NSScreen* screen = [pWindow screen];
  if ([screen respondsToSelector: @selector (backingScaleFactor)])
    displayScale = screen.backingScaleFactor;
  wp.x /= displayScale;
  wp.y /= displayScale;

  NSEvent* event = [NSEvent otherEventWithType:NSApplicationDefined
                  location:wp
                  modifierFlags:NSApplicationDefined
                  timestamp: (NSTimeInterval) 0
                  windowNumber: [pWindow windowNumber]
                  context: [NSGraphicsContext currentContext]
                    subtype:0
                    data1: 0
                    data2: 0];

  [NSMenu popUpContextMenu:nsMenu withEvent:event forView:dummyView];

  NSMenuItem* chosenItem = [dummyView MenuItem];
  NSMenu* chosenMenu = [chosenItem menu];
  IPopupMenu* associatedIPopupMenu = [(IGRAPHICS_NSMENU*) chosenMenu AssociatedIPopupMenu];

  int chosenItemIdx = [chosenMenu indexOfItem: chosenItem];

  if (chosenItemIdx > -1 && associatedIPopupMenu)
  {
    associatedIPopupMenu->SetChosenItemIdx(chosenItemIdx);
    return associatedIPopupMenu;
  }
  else return 0;
}

- (void) createTextEntry: (IControl*) pControl : (IParam*) pParam : (IText*) pText : (const char*) pString : (NSRect) areaRect;
{
  if (!pControl || mTextFieldView) return;

  mTextFieldView = [[NSTextField alloc] initWithFrame: areaRect];
  NSString* font = [NSString stringWithUTF8String: pText->mFont];
  [mTextFieldView setFont: [NSFont fontWithName:font size: (float) AdjustFontSize(pText->mSize)]];

  switch ( pText->mAlign )
  {
    case IText::kAlignNear:
      [mTextFieldView setAlignment: NSLeftTextAlignment];
      break;
    case IText::kAlignCenter:
      [mTextFieldView setAlignment: NSCenterTextAlignment];
      break;
    case IText::kAlignFar:
      [mTextFieldView setAlignment: NSRightTextAlignment];
      break;
    default:
      break;
  }

  // set up formatter
  if (pParam)
  {
    NSMutableCharacterSet *characterSet = [[NSMutableCharacterSet alloc] init];

    switch ( pParam->Type() )
    {
      case IParam::kTypeEnum:
      case IParam::kTypeInt:
      case IParam::kTypeBool:
        [characterSet addCharactersInString:@"0123456789-+"];
        break;
      case IParam::kTypeDouble:
        [characterSet addCharactersInString:@"0123456789.-+"];
        break;
      default:
        break;
    }

    [mTextFieldView setFormatter:[[[COCOA_FORMATTER alloc] init] autorelease]];
    [[mTextFieldView formatter] setAcceptableCharacterSet:characterSet];
    [[mTextFieldView formatter] setMaximumLength:pControl->GetTextEntryLength()];
    [characterSet release];
  }

  [[mTextFieldView cell] setLineBreakMode: NSLineBreakByTruncatingTail];
  [mTextFieldView setAllowsEditingTextAttributes:NO];
  [mTextFieldView setTextColor:ToNSColor(&pText->mTextEntryFGColor)];
  [mTextFieldView setBackgroundColor:ToNSColor(&pText->mTextEntryBGColor)];

  [mTextFieldView setStringValue: ToNSString(pString)];

#ifndef COCOA_TEXTENTRY_BORDERED
  [mTextFieldView setBordered: NO];
  [mTextFieldView setFocusRingType:NSFocusRingTypeNone];
#endif
  
#if __MAC_OS_X_VERSION_MAX_ALLOWED > 1050
  [mTextFieldView setDelegate: (id<NSTextFieldDelegate>) self];
#else
  [mTextFieldView setDelegate: self];
#endif
  
  [self addSubview: mTextFieldView];
  NSWindow* pWindow = [self window];
  [pWindow makeKeyAndOrderFront:nil];
  [pWindow makeFirstResponder: mTextFieldView];

  mEdParam = pParam; // might be 0
  mEdControl = pControl;
}

- (void) endUserInput
{
  [mTextFieldView setDelegate: nil];
  [mTextFieldView removeFromSuperview];

  NSWindow* pWindow = [self window];
  [pWindow makeFirstResponder: self];

  mTextFieldView = 0;
  mEdControl = 0;
  mEdParam = 0;
}

- (NSString*) view: (NSView*) pView stringForToolTip: (NSToolTipTag) tag point: (NSPoint) point userData: (void*) pData
{
  int c = mGraphics ? GetMouseOver(mGraphics) : -1;
  if (c < 0) return @"";
  
  const char* tooltip = mGraphics->GetControl(c)->GetTooltip();
  return CSTR_NOT_EMPTY(tooltip) ? ToNSString((const char*) tooltip) : @"";
}

- (void) registerToolTip: (IRECT*) pRECT
{
  [self addToolTipRect: ToNSRect(mGraphics, pRECT) owner: self userData: nil];
}

@end
