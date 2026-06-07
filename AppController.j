@import <AppKit/AppKit.j>
@import <Foundation/CPObject.j>

// Custom background color attributes for layout highlights
var CorrectionHighlightColorAttributeName = @"CorrectionHighlightColorAttributeName";
var CorrectionAlertIdentifierAttributeName = @"CorrectionAlertIdentifierAttributeName";

// Hilfsklasse für eine interaktive, neutrale Klickfläche ohne Standard-Highlighting
@implementation AlertCardBackgroundView : CPView
{
    id _target;
    SEL _action;
    id _representedObject @accessors(property=representedObject);
}

- (void)setTarget:(id)aTarget
{
    _target = aTarget;
}

- (void)setAction:(SEL)anAction
{
    _action = anAction;
}

- (void)mouseDown:(CPEvent)anEvent
{
    if (_target && _action && [_target respondsToSelector:_action])
    {
        [_target performSelector:_action withObject:self];
    }
}

@end

@implementation AppController : CPObject
{
    CPTextView          _editorTextView;
    CPScrollView        _sidebarScrollView;
    CPView              _sidebarDocumentView;
    CPButton            _analyzeButton;
    CPPopUpButton       _languagePopUp;
    CPTextField         _statusLabel;
    
    // Progress & Sheet Controls
    CPProgressIndicator _progressBar;
    CPButton            _transferButton;
    CPWindow            _sheetWindow;
    CPTextView          _sheetTextView;

    // Service Settings Controls
    CPWindow            _settingsWindow;
    CPPopUpButton       _servicePopUp;
    CPTextField         _endpointField;
    CPTextField         _modelField;
    CPTextField         _apiKeyField;

    // Temporary Settings Variables to preserve changes before saving
    CPString            _lastSelectedService;
    CPString            _tempOllamaEndpoint;
    CPString            _tempOllamaModel;
    CPString            _tempGroqAPIKey;
    CPString            _tempGroqModel;
    CPString            _tempGeminiAPIKey;
    CPString            _tempGeminiModel;
    CPString            _tempOpenRouterAPIKey;
    CPString            _tempOpenRouterModel;

    CPArray             _paragraphsData;  // Cached structured backend responses
    CPDictionary        _alertCardsMap;   // Maps alert IDs to their sidebar visual card boxes
    CPBox               _currentHighlightedCard; // Currently active/selected card in sidebar
    
    int                 _totalParagraphs;
    int                 _completedParagraphs;
}

- (void)orderFrontFontPanel:(id)sender
{
   [[CPFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    // --- PERSISTENT USER DEFAULTS INITIALIZATION ---
    var defaults = [CPUserDefaults standardUserDefaults];
    var defaultSettings = [CPDictionary dictionaryWithObjects:[
        @"http://localhost:11434/api/generate",
        @"gemma4:e4b",
        @"openrouter",
        @"",
        @"llama-3.1-8b-instant",
        @"",
        @"gemini-3.1-flash-lite",
        @"",
        @"google/gemini-3.1-flash-lite-preview"
    ] forKeys:[
        @"OllamaEndpoint",
        @"OllamaModel",
        @"ServiceType",
        @"GroqAPIKey",
        @"GroqModel",
        @"GeminiAPIKey",
        @"GeminiModel",
        @"OpenRouterAPIKey",
        @"OpenRouterModel"
    ]];
    [defaults registerDefaults:defaultSettings];

    // --- SYSTEM MENU BAR SETUP ---
    var mainMenu = [CPApp mainMenu];
    while ([mainMenu numberOfItems] > 0)
       [mainMenu removeItemAtIndex:0];

    // AI Assistant Menu
    var appItem = [mainMenu insertItemWithTitle:@"AI Assistant" action:nil keyEquivalent:nil atIndex:0];
    var appMenu = [[CPMenu alloc] initWithTitle:@"AI Assistant"];
    [appMenu addItemWithTitle:@"Settings..." action:@selector(openSettingsSheet:) keyEquivalent:@","];
    [mainMenu setSubmenu:appMenu forItem:appItem];

    // Format Menu with Font Panel
    var formatItem = [mainMenu insertItemWithTitle:@"Format" action:nil keyEquivalent:nil atIndex:1];
    var formatMenu = [[CPMenu alloc] initWithTitle:@"Format"];
    [formatMenu addItemWithTitle:@"Font Panel" action:@selector(orderFrontFontPanel:) keyEquivalent:@"t"];
    [mainMenu setSubmenu:formatMenu forItem:formatItem];
    [CPMenu setMenuBarVisible:YES];

    _alertCardsMap = [CPDictionary dictionary];

    var theWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(0, 0, 1100, 750) styleMask:CPBorderlessBridgeWindowMask];
    [theWindow setTitle:@"AI Writing Assistant"];
    [theWindow center];

    var contentView = [theWindow contentView];
    var bounds = [contentView bounds];

    // --- TOP ACTION BAR ---
    var topBar = [[CPView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(bounds), 50)];
    [topBar setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [topBar setBackgroundColor:[CPColor colorWithWhite:0.97 alpha:1.0]];
    [contentView addSubview:topBar];

    // Check Button
    _analyzeButton = [[CPButton alloc] initWithFrame:CGRectMake(20, 12, 130, 26)];
    [_analyzeButton setTitle:@"Check Document"];
    [_analyzeButton setTarget:self];
    [_analyzeButton setAction:@selector(analyzeDocument:)];
    [topBar addSubview:_analyzeButton];

    // Language Selector Popup
    _languagePopUp = [[CPPopUpButton alloc] initWithFrame:CGRectMake(160, 12, 95, 26) pullsDown:NO];
    [_languagePopUp addItemWithTitle:@"English"];
    [[_languagePopUp lastItem] setRepresentedObject:@"en"];
    [_languagePopUp addItemWithTitle:@"Deutsch"];
    [[_languagePopUp lastItem] setRepresentedObject:@"de"];
    [_languagePopUp addItemWithTitle:@"Français"];
    [[_languagePopUp lastItem] setRepresentedObject:@"fr"];
    [topBar addSubview:_languagePopUp];

    // Unified Session Import/Export Button
    _transferButton = [[CPButton alloc] initWithFrame:CGRectMake(265, 12, 140, 26)];
    [_transferButton setTitle:@"Import / Export JSON"];
    [_transferButton setTarget:self];
    [_transferButton setAction:@selector(openTransferSheet:)];
    [topBar addSubview:_transferButton];

    // Progress Bar
    _progressBar = [[CPProgressIndicator alloc] initWithFrame:CGRectMake(420, 18, 120, 14)];
    [_progressBar setStyle:CPProgressIndicatorBarStyle];
    [_progressBar setIndeterminate:NO];
    [_progressBar setHidden:YES];
    [topBar addSubview:_progressBar];

    // Status Label
    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(550, 15, 525, 20)];
    [_statusLabel setStringValue:@"Enter narrative text below and run validation."];
    [_statusLabel setFont:[CPFont systemFontOfSize:12]];
    [_statusLabel setAutoresizingMask:CPViewWidthSizable];
    [topBar addSubview:_statusLabel];

    // --- MAIN WORKING LAYOUT (SPLIT VIEW) ---
    var splitHeight = CGRectGetHeight(bounds) - 50;
    var splitView = [[CPSplitView alloc] initWithFrame:CGRectMake(0, 50, CGRectGetWidth(bounds), splitHeight)];
    [splitView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [splitView setVertical:YES];

    var dividerWidth = [splitView dividerThickness];
    var leftWidth = (CGRectGetWidth([splitView bounds]) - dividerWidth) * 0.65;
    var rightWidth = (CGRectGetWidth([splitView bounds]) - dividerWidth) - leftWidth;

    // LEFT: Document Editor Scroll View
    var editorScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, leftWidth, splitHeight)];
    [editorScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [editorScroll setAutohidesScrollers:YES];
    [editorScroll setHasHorizontalScroller:NO];

    _editorTextView = [[CPTextView alloc] initWithFrame:[editorScroll bounds]];
    [_editorTextView setAutoresizingMask:CPViewWidthSizable];
    [_editorTextView setMinSize:CGSizeMake(0, 0)];
    [_editorTextView setMaxSize:CGSizeMake(100000, 100000)];
    [_editorTextView setHorizontallyResizable:NO];
    [_editorTextView setVerticallyResizable:YES];
    [_editorTextView setRichText:YES];
    [_editorTextView setFont:[CPFont fontWithName:@"Arial" size:14.0]];
    [_editorTextView setDelegate:self];
    [_editorTextView setAutoresizingMask:CPViewWidthSizable];
    [[_editorTextView textContainer] setWidthTracksTextView:YES];

    [editorScroll setDocumentView:_editorTextView];
    [splitView addSubview:editorScroll];

    // RIGHT: Alert Sidebar Panel
    _sidebarScrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, splitHeight)];
    [_sidebarScrollView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_sidebarScrollView setAutohidesScrollers:YES];
    [_sidebarScrollView setHasHorizontalScroller:NO];
    [_sidebarScrollView setBackgroundColor:[CPColor colorWithWhite:0.96 alpha:1.0]];

    _sidebarDocumentView = [[CPView alloc] initWithFrame:CGRectMake(0, 0, rightWidth, 10)];
    [_sidebarDocumentView setAutoresizingMask:CPViewWidthSizable];
    [_sidebarScrollView setDocumentView:_sidebarDocumentView];
    [splitView addSubview:_sidebarScrollView];

    [contentView addSubview:splitView];
    [theWindow orderFront:self];

    // Sample initial text block
    [_editorTextView setString:@"Welcome to the GrammarMom Editor, the best place to write what's important.\n\nRed underlines mean that Grammarly has spotted a mistake in your writing. You'll see one if you mispell something. If you're worry about typos or grammatical errors that could effect your credibility, suggestions will helps you fix those to."];
}

// --- CONFIGURATION PANEL ---

- (void)openSettingsSheet:(id)sender
{
    if (!_settingsWindow)
    {
        _settingsWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(0, 0, 480, 290)
                                                   styleMask:CPTitledWindowMask | CPClosableWindowMask];
        
        var sheetContentView = [_settingsWindow contentView];
        var sheetBounds = [sheetContentView bounds];

        // Description Info
        var infoLabel = [[CPTextField alloc] initWithFrame:CGRectMake(15, 15, CGRectGetWidth(sheetBounds) - 30, 40)];
        [infoLabel setStringValue:@"Configure your LLM integration (Ollama, Groq, Gemini, or OpenRouter)."];
        [infoLabel setFont:[CPFont systemFontOfSize:11.0]];
        [infoLabel setTextColor:[CPColor colorWithWhite:0.3 alpha:1.0]];
        [infoLabel setLineBreakMode:CPLineBreakByWordWrapping];
        [sheetContentView addSubview:infoLabel];

        // Service Type
        var serviceLabel = [[CPTextField alloc] initWithFrame:CGRectMake(15, 60, 110, 20)];
        [serviceLabel setStringValue:@"Service Type:"];
        [serviceLabel setFont:[CPFont systemFontOfSize:12.0]];
        [serviceLabel setAlignment:CPRightTextAlignment];
        [sheetContentView addSubview:serviceLabel];

        _servicePopUp = [[CPPopUpButton alloc] initWithFrame:CGRectMake(135, 57, 150, 26) pullsDown:NO];
        [_servicePopUp addItemWithTitle:@"Ollama"];
        [[_servicePopUp lastItem] setRepresentedObject:@"ollama"];
        [_servicePopUp addItemWithTitle:@"Groq API"];
        [[_servicePopUp lastItem] setRepresentedObject:@"groq"];
        [_servicePopUp addItemWithTitle:@"Google Gemini"];
        [[_servicePopUp lastItem] setRepresentedObject:@"gemini"];
        [_servicePopUp addItemWithTitle:@"OpenRouter"];
        [[_servicePopUp lastItem] setRepresentedObject:@"openrouter"];
        [_servicePopUp setTarget:self];
        [_servicePopUp setAction:@selector(serviceTypeDidChange:)];
        [sheetContentView addSubview:_servicePopUp];

        // Endpoint Target URL
        var endpointLabel = [[CPTextField alloc] initWithFrame:CGRectMake(15, 95, 110, 20)];
        [endpointLabel setStringValue:@"Ollama API URL:"];
        [endpointLabel setFont:[CPFont systemFontOfSize:12.0]];
        [endpointLabel setAlignment:CPRightTextAlignment];
        [sheetContentView addSubview:endpointLabel];

        _endpointField = [[CPTextField alloc] initWithFrame:CGRectMake(135, 92, CGRectGetWidth(sheetBounds) - 155, 24)];
        [_endpointField setEditable:YES];
        [_endpointField setBezeled:YES];
        [_endpointField setFont:[CPFont systemFontOfSize:12.0]];
        [sheetContentView addSubview:_endpointField];

        // Model String Selector
        var modelLabel = [[CPTextField alloc] initWithFrame:CGRectMake(15, 130, 110, 20)];
        [modelLabel setStringValue:@"Model Name:"];
        [modelLabel setFont:[CPFont systemFontOfSize:12.0]];
        [modelLabel setAlignment:CPRightTextAlignment];
        [sheetContentView addSubview:modelLabel];

        _modelField = [[CPTextField alloc] initWithFrame:CGRectMake(135, 127, CGRectGetWidth(sheetBounds) - 155, 24)];
        [_modelField setEditable:YES];
        [_modelField setBezeled:YES];
        [_modelField setFont:[CPFont systemFontOfSize:12.0]];
        [sheetContentView addSubview:_modelField];

        // API Key Field
        var apiKeyLabel = [[CPTextField alloc] initWithFrame:CGRectMake(15, 165, 110, 20)];
        [apiKeyLabel setStringValue:@"API Key:"];
        [apiKeyLabel setFont:[CPFont systemFontOfSize:12.0]];
        [apiKeyLabel setAlignment:CPRightTextAlignment];
        [sheetContentView addSubview:apiKeyLabel];

        _apiKeyField = [[CPTextField alloc] initWithFrame:CGRectMake(135, 162, CGRectGetWidth(sheetBounds) - 155, 24)];
        [_apiKeyField setEditable:YES];
        [_apiKeyField setBezeled:YES];
        [_apiKeyField setFont:[CPFont systemFontOfSize:12.0]];
        [sheetContentView addSubview:_apiKeyField];

        // Action Buttons
        var btnY = CGRectGetHeight(sheetBounds) - 45;

        var cancelBtn = [[CPButton alloc] initWithFrame:CGRectMake(CGRectGetWidth(sheetBounds) - 205, btnY, 90, 26)];
        [cancelBtn setTitle:@"Cancel"];
        [cancelBtn setTarget:self];
        [cancelBtn setAction:@selector(closeSettingsSheet:)];
        [sheetContentView addSubview:cancelBtn];

        var saveBtn = [[CPButton alloc] initWithFrame:CGRectMake(CGRectGetWidth(sheetBounds) - 105, btnY, 90, 26)];
        [saveBtn setTitle:@"Save"];
        [saveBtn setTarget:self];
        [saveBtn setAction:@selector(saveSettings:)];
        [sheetContentView addSubview:saveBtn];
    }

    [_settingsWindow setTitle:@"AI Service Configuration"];
    
    var defaults = [CPUserDefaults standardUserDefaults];
    var activeService = [defaults objectForKey:@"ServiceType"] || @"ollama";
    _lastSelectedService = activeService;

    // Load saved settings into temporary working variables
    _tempOllamaEndpoint = [defaults objectForKey:@"OllamaEndpoint"] || @"http://localhost:11434/api/generate";
    _tempOllamaModel = [defaults objectForKey:@"OllamaModel"] || @"gemma4:e4b";
    _tempGroqAPIKey = [defaults objectForKey:@"GroqAPIKey"] || @"";
    _tempGroqModel = [defaults objectForKey:@"GroqModel"] || @"llama3-8b-8192";
    _tempGeminiAPIKey = [defaults objectForKey:@"GeminiAPIKey"] || @"";
    _tempGeminiModel = [defaults objectForKey:@"GeminiModel"] || @"gemini-2.0-flash";
    _tempOpenRouterAPIKey = [defaults objectForKey:@"OpenRouterAPIKey"] || @"";
    _tempOpenRouterModel = [defaults objectForKey:@"OpenRouterModel"] || @"openai/gpt-4o";

    if (activeService === @"ollama") [_servicePopUp selectItemAtIndex:0];
    else if (activeService === @"groq") [_servicePopUp selectItemAtIndex:1];
    else if (activeService === @"gemini") [_servicePopUp selectItemAtIndex:2];
    else if (activeService === @"openrouter") [_servicePopUp selectItemAtIndex:3];

    [self updateFieldsForService:activeService];

    [CPApp beginSheet:_settingsWindow
        modalForWindow:[_editorTextView window]
         modalDelegate:self
        didEndSelector:nil
           contextInfo:nil];
}

- (void)updateFieldsForService:(CPString)serviceType
{
    if (serviceType === @"ollama") {
        [_endpointField setEnabled:YES];
        [_endpointField setStringValue:_tempOllamaEndpoint];
        [_modelField setStringValue:_tempOllamaModel];
        [_apiKeyField setEnabled:NO];
        [_apiKeyField setStringValue:@""];
        [_apiKeyField setPlaceholderString:@"Not required for Ollama"];
    } else {
        [_endpointField setEnabled:NO];
        [_endpointField setStringValue:@""];
        [_endpointField setPlaceholderString:@"Constant Endpoint"];
        [_apiKeyField setEnabled:YES];
        [_apiKeyField setPlaceholderString:@"Enter API Key"];
        
        if (serviceType === @"groq") {
            [_modelField setStringValue:_tempGroqModel];
            [_apiKeyField setStringValue:_tempGroqAPIKey];
        } else if (serviceType === @"gemini") {
            [_modelField setStringValue:_tempGeminiModel];
            [_apiKeyField setStringValue:_tempGeminiAPIKey];
        } else if (serviceType === @"openrouter") {
            [_modelField setStringValue:_tempOpenRouterModel];
            [_apiKeyField setStringValue:_tempOpenRouterAPIKey];
        }
    }
}

- (void)serviceTypeDidChange:(id)sender
{
    // 1. Commit active fields to temporary storage before switching service variables
    if (_lastSelectedService === @"ollama") {
        _tempOllamaEndpoint = [_endpointField stringValue];
        _tempOllamaModel = [_modelField stringValue];
    } else if (_lastSelectedService === @"groq") {
        _tempGroqModel = [_modelField stringValue];
        _tempGroqAPIKey = [_apiKeyField stringValue];
    } else if (_lastSelectedService === @"gemini") {
        _tempGeminiModel = [_modelField stringValue];
        _tempGeminiAPIKey = [_apiKeyField stringValue];
    } else if (_lastSelectedService === @"openrouter") {
        _tempOpenRouterModel = [_modelField stringValue];
        _tempOpenRouterAPIKey = [_apiKeyField stringValue];
    }

    // 2. Load fields for newly selected service
    var newService = [[_servicePopUp selectedItem] representedObject];
    _lastSelectedService = newService;
    [self updateFieldsForService:newService];
}

- (void)closeSettingsSheet:(id)sender
{
    [CPApp endSheet:_settingsWindow];
    [_settingsWindow orderOut:self];
}

- (void)saveSettings:(id)sender
{
    // First, commit active fields to temporary variables
    var activeService = [[_servicePopUp selectedItem] representedObject] || @"ollama";
    if (activeService === @"ollama") {
        _tempOllamaEndpoint = [_endpointField stringValue];
        _tempOllamaModel = [_modelField stringValue];
    } else if (activeService === @"groq") {
        _tempGroqModel = [_modelField stringValue];
        _tempGroqAPIKey = [_apiKeyField stringValue];
    } else if (activeService === @"gemini") {
        _tempGeminiModel = [_modelField stringValue];
        _tempGeminiAPIKey = [_apiKeyField stringValue];
    } else if (activeService === @"openrouter") {
        _tempOpenRouterModel = [_modelField stringValue];
        _tempOpenRouterAPIKey = [_apiKeyField stringValue];
    }

    // Persist all configured settings to standard user defaults
    var defaults = [CPUserDefaults standardUserDefaults];
    [defaults setObject:activeService forKey:@"ServiceType"];
    [defaults setObject:_tempOllamaEndpoint forKey:@"OllamaEndpoint"];
    [defaults setObject:_tempOllamaModel forKey:@"OllamaModel"];
    [defaults setObject:_tempGroqModel forKey:@"GroqModel"];
    [defaults setObject:_tempGroqAPIKey forKey:@"GroqAPIKey"];
    [defaults setObject:_tempGeminiModel forKey:@"GeminiModel"];
    [defaults setObject:_tempGeminiAPIKey forKey:@"GeminiAPIKey"];
    [defaults setObject:_tempOpenRouterModel forKey:@"OpenRouterModel"];
    [defaults setObject:_tempOpenRouterAPIKey forKey:@"OpenRouterAPIKey"];
    
    [self closeSettingsSheet:sender];
    [_statusLabel setStringValue:@"AI configuration updated and saved."];
}

// --- UNIFIED IMPORT & EXPORT SESSION DATA ---

- (void)openTransferSheet:(id)sender
{
    if (!_sheetWindow)
    {
        _sheetWindow = [[CPWindow alloc] initWithContentRect:CGRectMake(0, 0, 580, 460)
                                                   styleMask:CPTitledWindowMask | CPClosableWindowMask | CPResizableWindowMask];
        
        var sheetContentView = [_sheetWindow contentView];
        var sheetBounds = [sheetContentView bounds];

        // Description Label
        var infoLabel = [[CPTextField alloc] initWithFrame:CGRectMake(15, 10, CGRectGetWidth(sheetBounds) - 30, 45)];
        [infoLabel setStringValue:@"To export, copy the JSON block below. To import a past run, replace the JSON content below and click \"Import JSON\"."];
        [infoLabel setFont:[CPFont systemFontOfSize:11.0]];
        [infoLabel setTextColor:[CPColor colorWithWhite:0.3 alpha:1.0]];
        [infoLabel setLineBreakMode:CPLineBreakByWordWrapping];
        [infoLabel setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
        [sheetContentView addSubview:infoLabel];

        // Scroll View for JSON text area
        var scroll = [[CPScrollView alloc] initWithFrame:CGRectMake(15, 60, CGRectGetWidth(sheetBounds) - 30, CGRectGetHeight(sheetBounds) - 130)];
        [scroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [scroll setAutohidesScrollers:YES];

        _sheetTextView = [[CPTextView alloc] initWithFrame:[scroll bounds]];
        [_sheetTextView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_sheetTextView setFont:[CPFont fontWithName:@"Courier" size:11.0]];
        [_sheetTextView setRichText:NO];
        [scroll setDocumentView:_sheetTextView];
        [sheetContentView addSubview:scroll];

        // Bottom Buttons
        var btnY = CGRectGetHeight(sheetBounds) - 50;

        var cancelBtn = [[CPButton alloc] initWithFrame:CGRectMake(CGRectGetWidth(sheetBounds) - 235, btnY, 110, 26)];
        [cancelBtn setTitle:@"Cancel / Close"];
        [cancelBtn setAutoresizingMask:CPViewMinXMargin | CPViewMinYMargin];
        [cancelBtn setTarget:self];
        [cancelBtn setAction:@selector(closeSheet:)];
        [sheetContentView addSubview:cancelBtn];

        var actionBtn = [[CPButton alloc] initWithFrame:CGRectMake(CGRectGetWidth(sheetBounds) - 115, btnY, 100, 26)];
        [actionBtn setTitle:@"Import JSON"];
        [actionBtn setAutoresizingMask:CPViewMinXMargin | CPViewMinYMargin];
        [actionBtn setTarget:self];
        [actionBtn setAction:@selector(executeImportAction:)];
        [sheetContentView addSubview:actionBtn];
    }

    [_sheetWindow setTitle:@"Transfer Session Data (JSON)"];
    [_sheetTextView setEditable:YES];

    // Assemble document structure and validation response mapping into transfer JSON
    var sessionState = {
        "editorText": [_editorTextView string],
        "paragraphsData": _paragraphsData || []
    };
    
    var jsonString = JSON.stringify(sessionState, null, 2);
    [_sheetTextView setString:jsonString];

    [CPApp beginSheet:_sheetWindow
        modalForWindow:[_editorTextView window]
         modalDelegate:self
        didEndSelector:nil
           contextInfo:nil];
           
    window.setTimeout(function() { [_sheetTextView selectAll:self]; }, 100);
}

- (void)closeSheet:(id)sender
{
    [CPApp endSheet:_sheetWindow];
    [_sheetWindow orderOut:self];
}

- (void)executeImportAction:(id)sender
{
    var text = [_sheetTextView string];
    if (text && [text length] > 0)
    {
        try {
            var sessionData = JSON.parse(text);
            if (sessionData && typeof sessionData === "object") {
                if (sessionData.editorText !== undefined) {
                    [_editorTextView setString:sessionData.editorText];
                }
                
                if (sessionData.paragraphsData && Array.isArray(sessionData.paragraphsData)) {
                    _paragraphsData = sessionData.paragraphsData;
                } else {
                    _paragraphsData = [];
                }

                // Render highlighting and populate sidebar container directly
                [self renderHighlightsAndSidebar];
                [_statusLabel setStringValue:@"Session state loaded successfully."];
            } else {
                [_statusLabel setStringValue:@"Failed to load state: invalid structure format."];
            }
        } catch (e) {
            [_statusLabel setStringValue:@"JSON structural format analysis failed."];
            CPLog.error(@"JSON Parsing Exception: " + e.message);
        }
    }
    [self closeSheet:sender];
}

// --- PROMPTS FOR THE AI SERVICES (BROUGHT TO FRONTEND) ---

- (CPString)promptForLanguage:(CPString)langCode text:(CPString)pText
{
    var lines = [];
    if (langCode === @"de") {
        lines = [
            "Sie sind ein kontextsensitiver Korrektur- und Lektoratsassistent.",
            "Analysieren Sie den bereitgestellten Textabschnitt und geben Sie eine JSON-Liste der identifizierten Probleme zurück.",
            "",
            "Analysieren Sie den Text auf vier Kategorien:",
            "1. „spelling“: Tippfehler, Rechtschreibfehler und häufige Falschschreibungen.",
            "2. „grammar“: Subjekt-Verb-Kongruenz, Zeichensetzungsfehler, Syntaxfehler, unpassende Tempuswechsel.",
            "3. „clarity“: Zu verschachtelte Sätze, Passivkonstruktionen, unklare Strukturen.",
            "4. „style“: Tonfall-Optimierung, Anpassung an formelleres Vokabular oder Verstöße gegen Stilrichtlinien.",
            "",
            "WICHTIGE ANWEISUNGEN:",
            "- Das Feld \"original_text\" muss exakt dem fehlerhaften Wort oder Satzteil aus dem bereitgestellten Text entsprechen.",
            "- Geben Sie AUSSCHLIESSLICH gültiges, reines JSON aus, das ein flaches Array von Objekten gemäß dem unten stehenden Schema enthält.",
            "- Verwenden Sie keine Markdown-Code-Blöcke (wie ```json) und fügen Sie keinen zusätzlichen Text vor oder nach dem JSON-Objekt an.",
            "",
            "JSON-Schema für das Ausgabeformat:",
            "[",
            "  {",
            "    \"category\": \"spelling\" | \"grammar\" | \"clarity\" | \"style\",",
            "    \"title\": \"Kurze Beschreibung der Kategorie\",",
            "    \"original_text\": \"exakter_originaler_text_aus_dem_dokument\",",
            "    \"suggested_text\": \"vorgeschlagener_ersatztext\",",
            "    \"explanation\": \"Kurze Erklärung, warum diese Korrektur empfohlen wird.\"",
            "  }",
            "]",
            "",
            "Hier ist dein Text:",
            pText
        ];
    } else if (langCode === @"fr") {
        lines = [
            "Vous êtes un assistant de relecture et de correction de texte sensible au contexte.",
            "Analysez le paragraphe fourni et retournez une liste JSON des problèmes identifiés.",
            "",
            "Analysez le texte selon quatre catégories :",
            "1. \"spelling\" : Fautes de frappe, erreurs d'orthographe et mots mal orthographiés.",
            "2. \"grammar\" : Accord sujet-verbe, mauvaise ponctuation, erreurs de syntaxe, incohérences de temps.",
            "3. \"clarity\" : Phrases trop longues, voix passive, structures confuses.",
            "4. \"style\" : Améliorations de ton, ajustements de vocabulaire formel ou violations des guides de style.",
            "",
            "CONSIGNES CRITIQUES :",
            "- Le champ \"original_text\" doit correspondre exactement au mot ou à la phrase incorrecte du paragraphe fourni.",
            "- Fournissez UNIQUEMENT du JSON brut et valide contenant un tableau plat d'objets conforme au schéma ci-dessous.",
            "- Ne générez pas de blocs de code Markdown (comme ```json) ni de texte conversationnel supplémentaire.",
            "",
            "Format de schéma JSON de sortie :",
            "[",
            "  {",
            "    \"category\": \"spelling\" | \"grammar\" | \"clarity\" | \"style\",",
            "    \"title\": \"Brève description de la catégorie\",",
            "    \"original_text\": \"texte_original_exact_provenant_du_document\",",
            "    \"suggested_text\": \"proposition_de_remplacement\",",
            "    \"explanation\": \"Brève explication du contexte justifiant cette correction.\"",
            "  }",
            "]",
            "",
            "Voici votre texte :",
            pText
        ];
    } else {
        lines = [
            "You are a context-aware proofreading and copy-editing assistant.",
            "Analyze the provided text paragraph and return a JSON list of identified issues.",
            "",
            "Analyze for four categories:",
            "1. \"spelling\": Typos, orthography errors, and common misspellings.",
            "2. \"grammar\": Subject-verb agreement, misuse of punctuation, syntax errors, tense inconsistencies.",
            "3. \"clarity\": Wordy sentences, passive voice, confusing structures.",
            "4. \"style\": Tone improvements, formal vocabulary adjustments, or style-guide violations.",
            "",
            "CRITICAL INSTRUCTIONS:",
            "- The \"original_text\" field must match the exact incorrect word or phrase from the provided paragraph text.",
            "- Output ONLY valid, raw JSON containing a flat array of objects matching the schema below.",
            "- Do not output markdown code blocks (such as ```json) or trailing conversational text.",
            "",
            "JSON Schema Output format:",
            "[",
            "  {",
            "    \"category\": \"spelling\" | \"grammar\" | \"clarity\" | \"style\",",
            "    \"title\": \"Short category description\",",
            "    \"original_text\": \"exact_original_text_from_the_document\",",
            "    \"suggested_text\": \"proposed_replacement\",",
            "    \"explanation\": \"Brief context explaining why this correction is recommended.\"",
            "  }",
            "]",
            "",
            "Here is your text:",
            pText
        ];
    }
    return lines.join("\n");
}

// --- PROGRESSIVE DOCUMENT ANALYSIS ---

- (void)analyzeDocument:(id)sender
{
    var documentText = [_editorTextView string];
    if (!documentText || [documentText length] === 0) {
        [_statusLabel setStringValue:@"Please enter text before analyzing."];
        return;
    }

    // Splittet bei doppelten Zeilenumbrüchen ODER bei einem Punkt, gefolgt von einem Zeilenumbruch und einem Großbuchstaben
    var paragraphs = documentText.split(/(?:\r?\n\r?\n+)|(?<=\.)\r?\n(?=\p{Lu})/u);
    _totalParagraphs = paragraphs.length;
    _completedParagraphs = 0;

    _paragraphsData = [];
    for (var i = 0; i < _totalParagraphs; i++) {
        _paragraphsData.push({ "text": paragraphs[i], "alerts": [], "completed": false });
    }

    [_alertCardsMap removeAllObjects];
    _currentHighlightedCard = nil;
    
    var textStorage = [_editorTextView textStorage];
    var completeDocRange = CPMakeRange(0, [textStorage length]);
    [textStorage removeAttribute:CPBackgroundColorAttributeName range:completeDocRange];
    [textStorage removeAttribute:CorrectionAlertIdentifierAttributeName range:completeDocRange];
    [[_sidebarDocumentView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];

    [_progressBar setHidden:NO];
    [_progressBar setMaxValue:_totalParagraphs];
    [_progressBar setDoubleValue:0];

    [_analyzeButton setEnabled:NO];
    [_languagePopUp setEnabled:NO];
    [_transferButton setEnabled:NO];
    [_statusLabel setStringValue:@"Analyzing document... Progress: 0%"];

    var langCode = [[_languagePopUp selectedItem] representedObject] || @"en";

    for (var i = 0; i < _totalParagraphs; i++) {
        [self analyzeParagraph:paragraphs[i] index:i langCode:langCode];
    }
}

- (void)analyzeParagraph:(CPString)pText index:(int)pIndex langCode:(CPString)langCode
{
    // Ignore paragraphs containing only a few words (e.g. headings with 4 or fewer words)
    var words = pText.split(/\s+/);
    if (words.length <= 4) {
        var emptyResult = {
            "text": pText,
            "alerts": [],
            "completed": true
        };
        [self paragraphAnalysisDidFinish:emptyResult atIndex:pIndex];
        return;
    }

    var fullPrompt = [self promptForLanguage:langCode text:pText];

    var defaults = [CPUserDefaults standardUserDefaults];
    var serviceType = [defaults objectForKey:@"ServiceType"] || @"ollama";
    var endpoint = [defaults objectForKey:@"OllamaEndpoint"] || @"";
    var model = @"";
    var apiKey = @"";

    var reqUrl = @"";
    var headers = {};
    var payload = {};

    if (serviceType === @"groq") {
        model = [defaults objectForKey:@"GroqModel"] || @"llama3-8b-8192";
        apiKey = [defaults objectForKey:@"GroqAPIKey"] || @"";
        reqUrl = "https://api.groq.com/openai/v1/chat/completions";
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + apiKey
        };
        payload = {
            "model": model,
            "messages": [
                { "role": "user", "content": fullPrompt }
            ],
            "temperature": 0,
            "stream": false
        };
    } else if (serviceType === @"gemini") {
        model = [defaults objectForKey:@"GeminiModel"] || @"gemini-2.0-flash";
        apiKey = [defaults objectForKey:@"GeminiAPIKey"] || @"";
        reqUrl = "https://generativelanguage.googleapis.com/v1beta/models/" + model + ":generateContent?key=" + apiKey;
        headers = {
            "Content-Type": "application/json"
        };
        payload = {
            "contents": [{
                "parts": [{ "text": fullPrompt }]
            }],
            "generationConfig": {
                "temperature": 0.1
            }
        };
    } else if (serviceType === @"openrouter") {
        model = [defaults objectForKey:@"OpenRouterModel"] || @"openai/gpt-4o";
        apiKey = [defaults objectForKey:@"OpenRouterAPIKey"] || @"";
        reqUrl = "https://openrouter.ai/api/v1/chat/completions";
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + apiKey,
            "HTTP-Referer": "http://localhost:3000",
            "X-Title": "AI Writing Assistant"
        };
        payload = {
            "model": model,
            "messages": [
                { "role": "user", "content": fullPrompt }
            ],
            "temperature": 0.1,
            "stream": false
        };
    } else { // ollama
        model = [defaults objectForKey:@"OllamaModel"] || @"gemma4:e4b";
        reqUrl = endpoint || @"http://localhost:11434/api/generate";
        headers = {
            "Content-Type": "application/json"
        };
        payload = {
            "model": model,
            "prompt": fullPrompt,
            "stream": false,
            "options": {
                "temperature": 0,
                "num_ctx": 40000
            }
        };
    }

    var selfRef = self; // Keep safe reference for Javascript Async block callback

    // Native browser-based fetch to enable browser-only usage (eliminates Perl Backend dependency)
    fetch(reqUrl, {
        method: 'POST',
        headers: headers,
        body: JSON.stringify(payload)
    })
    .then(function(response) {
        if (!response.ok) {
            throw new Error("HTTP error! Status: " + response.status);
        }
        return response.json();
    })
    .then(function(data) {
        var responseText = "";

        if (serviceType === "groq" || serviceType === "openrouter") {
            responseText = (data.choices && data.choices[0] && data.choices[0].message) ? data.choices[0].message.content : "";
        } else if (serviceType === "gemini") {
            responseText = (data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts) ? data.candidates[0].content.parts[0].text : "";
        } else { // ollama
            responseText = data.response || "";
        }

        // Clean markdown indicators
        responseText = responseText.replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();

        var rawAlerts = [];
        try {
            rawAlerts = JSON.parse(responseText);
        } catch (e) {
            CPLog.error(@"JSON Parsing Exception inside browser-only parser: " + e.message);
        }

        var processedAlerts = [];
        var id_counter = 0;

        for (var i = 0; i < rawAlerts.length; i++) {
            var alert = rawAlerts[i];
            var orig = alert.original_text;
            if (!orig || orig === "") continue;

            var offset = pText.indexOf(orig);
            if (offset === -1) {
                offset = pText.toLowerCase().indexOf(orig.toLowerCase());
            }

            if (offset !== -1) {
                alert.offset = offset;
                alert.length = orig.length;
                alert.id = "alert_" + pIndex + "_" + id_counter++;
                processedAlerts.push(alert);
            }
        }

        var completedResult = {
            "text": pText,
            "alerts": processedAlerts,
            "completed": true
        };

        [selfRef paragraphAnalysisDidFinish:completedResult atIndex:pIndex];
    })
    .catch(function(error) {
        CPLog.error(@"AI Processing failed on API side for paragraph " + pIndex + @". Error: " + error);
        var failedResult = {
            "text": pText,
            "alerts": [],
            "completed": true
        };
        [selfRef paragraphAnalysisDidFinish:failedResult atIndex:pIndex];
    });
}

- (void)paragraphAnalysisDidFinish:(id)processedData atIndex:(int)pIndex
{
    _paragraphsData[pIndex] = processedData;
    _completedParagraphs++;
    [_progressBar setDoubleValue:_completedParagraphs];

    var percent = Math.round((_completedParagraphs / _totalParagraphs) * 100);
    [_statusLabel setStringValue:@"Analyzing document... Progress: " + percent + "%"];

    [self renderHighlightsAndSidebar];

    if (_completedParagraphs === _totalParagraphs) {
        [_analyzeButton setEnabled:YES];
        [_languagePopUp setEnabled:YES];
        [_transferButton setEnabled:YES];
        [_progressBar setHidden:YES];
        [_statusLabel setStringValue:@"Analysis finalized. Correct highlighted segments."];
    }
}

- (void)renderHighlightsAndSidebar
{
    [_alertCardsMap removeAllObjects];
    _currentHighlightedCard = nil;

    var textStorage = [_editorTextView textStorage];
    var completeDocRange = CPMakeRange(0, [textStorage length]);
    [textStorage removeAttribute:CPBackgroundColorAttributeName range:completeDocRange];
    [textStorage removeAttribute:CorrectionAlertIdentifierAttributeName range:completeDocRange];

    [[_sidebarDocumentView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];

    var sidebarWidth = CGRectGetWidth([_sidebarScrollView bounds]) - 20;
    var currentY = 15;
    var docString = [_editorTextView string];

    for (var i = 0; i < _paragraphsData.length; i++) {
        var pData = _paragraphsData[i];
        if (!pData || !pData.completed) {
            continue;
        }
        var pText = pData.text;

        var absoluteParaOffset = [docString rangeOfString:pText].location;
        if (absoluteParaOffset === CPNotFound) {
            continue;
        }

        var alerts = pData.alerts;
        for (var j = 0; j < alerts.length; j++) {
            var alert = alerts[j];
            var absRange = CPMakeRange(absoluteParaOffset + alert.offset, alert.length);

            var highlightColor = [CPColor colorWithRed:1.0 green:0.90 blue:0.90 alpha:1.0]; // Spelling
            if (alert.category === @"grammar") {
                highlightColor = [CPColor colorWithRed:0.90 green:0.95 blue:1.0 alpha:1.0]; // Grammar
            } else if (alert.category === @"clarity") {
                highlightColor = [CPColor colorWithRed:0.92 green:1.0 blue:0.92 alpha:1.0]; // Clarity
            } else if (alert.category === @"style") {
                highlightColor = [CPColor colorWithRed:0.97 green:0.92 blue:1.0 alpha:1.0]; // Style
            }

            [textStorage addAttribute:CPBackgroundColorAttributeName value:highlightColor range:absRange];
            [textStorage addAttribute:CorrectionAlertIdentifierAttributeName value:alert.id range:absRange];

            var card = [self createAlertCardFrame:CGRectMake(10, currentY, sidebarWidth, 110) forAlert:alert paragraphIndex:i];
            [_sidebarDocumentView addSubview:card];
            
            [_alertCardsMap setObject:card forKey:alert.id];
            currentY += 125;
        }
    }

    [_sidebarDocumentView setFrameSize:CGSizeMake(sidebarWidth + 20, currentY + 30)];
}

- (CPView)createAlertCardFrame:(CGRect)frame forAlert:(id)alert paragraphIndex:(int)pIndex
{
    var cardBox = [[CPBox alloc] initWithFrame:frame];
    
    [cardBox setBoxType:CPBoxCustom];
    [cardBox setBorderType:CPLineBorder];
    [cardBox setBorderWidth:1.0];
    [cardBox setBorderColor:[CPColor colorWithWhite:0.85 alpha:1.0]];
    [cardBox setCornerRadius:5.0];
    [cardBox setTitle:alert.title];
    [cardBox setAutoresizingMask:CPViewWidthSizable];

    var container = [cardBox contentView];
    var contentWidth = CGRectGetWidth([container bounds]);

    var cardBgColor = [CPColor colorWithRed:1.0 green:0.90 blue:0.90 alpha:1.0]; // Spelling
    var accentColor = [CPColor colorWithRed:1.0 green:0.40 blue:0.40 alpha:1.0];
    
    if (alert.category === @"grammar") {
        cardBgColor = [CPColor colorWithRed:0.90 green:0.95 blue:1.0 alpha:1.0];
        accentColor = [CPColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:1.0];
    } else if (alert.category === @"clarity") {
        cardBgColor = [CPColor colorWithRed:0.92 green:1.0 blue:0.92 alpha:1.0];
        accentColor = [CPColor colorWithRed:0.20 green:0.80 blue:0.20 alpha:1.0];
    } else if (alert.category === @"style") {
        cardBgColor = [CPColor colorWithRed:0.97 green:0.92 blue:1.0 alpha:1.0];
        accentColor = [CPColor colorWithRed:0.70 green:0.30 blue:0.90 alpha:1.0];
    }

    [cardBox setFillColor:cardBgColor];

    // Transparenter Klickhintergrund über die gesamte Inhaltsbox
    var bgClickView = [[AlertCardBackgroundView alloc] initWithFrame:[container bounds]];
    [bgClickView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [bgClickView setTarget:self];
    [bgClickView setAction:@selector(selectAlertTextAction:)];
    [bgClickView setRepresentedObject:{ "alert": alert, "paragraphIndex": pIndex }];
    [container addSubview:bgClickView positioned:CPWindowBelow relativeTo:nil];

    // Beschreibungstext (Hit-Tests sind deaktiviert, um Klicks an bgClickView weiterzuleiten)
    var description = [[CPTextField alloc] initWithFrame:CGRectMake(15, 5, contentWidth - 25, 45)];
    [description setStringValue:alert.explanation];
    [description setLineBreakMode:CPLineBreakByWordWrapping];
    [description setFont:[CPFont systemFontOfSize:11.0]];
    [description setTextColor:[CPColor colorWithWhite:0.25 alpha:1.0]];
    [description setHitTests:NO];
    [container addSubview:description];

    // Aktions-Button
    var actionBtn = [[CPButton alloc] initWithFrame:CGRectMake(15, 52, contentWidth - 50, 26)];
    [actionBtn setTitle:[CPString stringWithFormat:@"Correct to: '%@'", alert.suggested_text]];
    [actionBtn setFont:[CPFont boldSystemFontOfSize:11.0]];
    [actionBtn setTarget:self];
    [actionBtn setAction:@selector(applyCorrectionAction:)];
    actionBtn._representedObject = { "alert": alert, "paragraphIndex": pIndex };
    [container addSubview:actionBtn];

    return cardBox;
}

- (void)selectAlertTextAction:(id)sender
{
    var context = [sender representedObject];
    if (!context) return;
    var alert = context.alert;
    var pIndex = context.paragraphIndex;

    var docString = [_editorTextView string];
    var pData = _paragraphsData[pIndex];
    if (!pData) return;
    
    var pText = pData.text;
    var absoluteParaOffset = [docString rangeOfString:pText].location;
    if (absoluteParaOffset === CPNotFound) {
        return;
    }

    var absRange = CPMakeRange(absoluteParaOffset + alert.offset, alert.length);
    [_editorTextView setSelectedRange:absRange];
    
    // Scroll editor to visible passage
    [_editorTextView scrollRangeToVisible:absRange];
    
    [[_editorTextView window] makeFirstResponder:_editorTextView];
}

- (void)textViewDidChangeSelection:(CPNotification)aNotification
{
    var selectedRange = [_editorTextView selectedRange];
    if (selectedRange.length < 0 || !_paragraphsData) {
        return;
    }

    var docString = [_editorTextView string];
    var cursorLoc = selectedRange.location;

    if (_currentHighlightedCard) {
        [_currentHighlightedCard setBorderWidth:1.0];
        [_currentHighlightedCard setBorderColor:[CPColor colorWithWhite:0.85 alpha:1.0]];
        _currentHighlightedCard = nil;
    }

    for (var i = 0; i < _paragraphsData.length; i++) {
        var pData = _paragraphsData[i];
        if (!pData || !pData.completed) continue;
        
        var pText = pData.text;
        var absoluteParaOffset = [docString rangeOfString:pText].location;
        if (absoluteParaOffset === CPNotFound) {
            continue;
        }

        var MathAlerts = pData.alerts;
        for (var j = 0; j < MathAlerts.length; j++) {
            var alert = MathAlerts[j];
            var alertStart = absoluteParaOffset + alert.offset;
            var alertEnd = alertStart + alert.length;

            if (cursorLoc >= alertStart && cursorLoc <= alertEnd) {
                var activeCard = [_alertCardsMap objectForKey:alert.id];
                if (activeCard) {
                    var strongBorderColor = [CPColor colorWithRed:1.0 green:0.40 blue:0.40 alpha:1.0];
                    if (alert.category === @"grammar") {
                        strongBorderColor = [CPColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:1.0];
                    } else if (alert.category === @"clarity") {
                        strongBorderColor = [CPColor colorWithRed:0.20 green:0.80 blue:0.20 alpha:1.0];
                    } else if (alert.category === @"style") {
                        strongBorderColor = [CPColor colorWithRed:0.70 green:0.30 blue:0.90 alpha:1.0];
                    }

                    [activeCard setBorderWidth:2.5];
                    [activeCard setBorderColor:strongBorderColor];
                    _currentHighlightedCard = activeCard;

                    var cardFrame = [activeCard frame];
                    [[_sidebarScrollView contentView] scrollToPoint:CGPointMake(0, MAX(0, cardFrame.origin.y - 15))];
                }
                return;
            }
        }
    }
}

- (void)applyCorrectionAction:(id)sender
{
    var context = sender._representedObject;
    var alert = context.alert;
    var pIndex = context.paragraphIndex;

    var docString = [_editorTextView string];
    var pData = _paragraphsData[pIndex];
    if (!pData) return;
    
    var pText = pData.text;
    var absoluteParaOffset = [docString rangeOfString:pText].location;
    if (absoluteParaOffset === CPNotFound) {
        [_statusLabel setStringValue:@"Context mismatch. Please re-run check."];
        return;
    }

    var absRange = CPMakeRange(absoluteParaOffset + alert.offset, alert.length);

    [_editorTextView setSelectedRange:absRange];
    [_editorTextView insertText:alert.suggested_text];

    var lengthDelta = [alert.suggested_text length] - alert.length;
    var alerts = pData.alerts;

    for (var i = 0; i < alerts.length; i++) {
        if (alerts[i].offset > alert.offset) {
            alerts[i].offset += lengthDelta;
        }
    }

    var originalLength = [pText length];
    var preStr = [pText substringToIndex:alert.offset];
    var postStr = [pText substringFromIndex:alert.offset + alert.length];
    pData.text = preStr + alert.suggested_text + postStr;

    [pData.alerts removeObject:alert];

    [self renderHighlightsAndSidebar];
    
    // Focus and scroll corrected range
    var newRange = CPMakeRange(absoluteParaOffset + alert.offset, [alert.suggested_text length]);
    [_editorTextView scrollRangeToVisible:newRange];

    [_statusLabel setStringValue:@"Correction successfully applied."];
}

@end
