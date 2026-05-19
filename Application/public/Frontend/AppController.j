/*
 * Cappuccino frontend for PatchbayLLM (new version with upload)
 *
 * Created by daboe01 on 2025 by Daniel Boehringer.
 * Copyright 2025, All rights reserved.
 *
 *
 */



/////////////////////////////////////////////////////////

// Extract prefix from window.location.pathname
function extractPrefix() {
    var pathname = window.location.pathname;

    // If pathname ends with /Frontend/index.html, extract the prefix
    if (pathname.endsWith('/Frontend/index.html')) {
        var prefix = pathname.substring(0, pathname.length - '/Frontend/index.html'.length);
        return prefix === '' ? '' : prefix;
    }

    // If pathname ends with /Frontend/, extract the prefix
    if (pathname.endsWith('/Frontend/')) {
        var prefix = pathname.substring(0, pathname.length - '/Frontend/'.length);
        return prefix === '' ? '' : prefix;
    }

    // If pathname ends with /Frontend, extract the prefix
    if (pathname.endsWith('/Frontend')) {
        var prefix = pathname.substring(0, pathname.length - '/Frontend'.length);
        return prefix === '' ? '' : prefix;
    }

    // Default: no prefix
    return '';
}

var URLPrefix = extractPrefix();
HostURL = URLPrefix;
BaseURL = HostURL + "/";

/////////////////////////////////////////////////////////

@import <Foundation/CPObject.j>
@import <Renaissance/Renaissance.j>
@import "TNGrowlCenter.j";
@import "TNGrowlView.j";
@import "LaceViewController.j";
@import <Cup/Cup.j>

// A simple view to render the job status in the table
@implementation DailyProgressView : CPView
{
    CPProgressIndicator progressBar;
    CPTextField         statsLabel;
}

- (id)initWithFrame:(CGRect)aFrame
{
    self = [super initWithFrame:aFrame];
    if (self)
    {
        // Stats Label (e.g., "500/1000 (5 Failed)")
        statsLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0, 2, 120, 24)];
        [statsLabel setFont:[CPFont systemFontOfSize:10]];
        [statsLabel setAlignment:CPRightTextAlignment];
        [self addSubview:statsLabel];

        // Progress Bar
        progressBar = [[CPProgressIndicator alloc] initWithFrame:CGRectMake(125, 4, CGRectGetWidth(aFrame) - 130, 16)];
        [progressBar setIndeterminate:NO]; 
        [progressBar setControlSize:CPRegularControlSize];
        [progressBar setMinValue:0.0];
        [self addSubview:progressBar];
    }
    return self;
}

// Restore ivars when the table view clones the prototype
- (id)initWithCoder:(CPCoder)aCoder
{
    self = [super initWithCoder:aCoder];
    if (self)
    {
        progressBar = [aCoder decodeObjectForKey:@"progressBar"];
        statsLabel = [aCoder decodeObjectForKey:@"statsLabel"];
    }
    return self;
}

// FIX: Save ivars so they can be cloned
- (void)encodeWithCoder:(CPCoder)aCoder
{
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:progressBar forKey:@"progressBar"];
    [aCoder encodeObject:statsLabel forKey:@"statsLabel"];
}

- (void)setObjectValue:(id)anObject
{
    // Guard against null/undefined
    if (!anObject) return;

    // anObject is a plain JS object, so we access properties directly
    var total    = anObject.total || 0;
    var finished = anObject.finished || 0;
    var failed   = anObject.failed || 0;
    var active   = anObject.active || 0;

    // Calculate max value for the bar
    [progressBar setMaxValue:1];
    
    // Safety check for divide by zero
    if (total > 0)
        [progressBar setDoubleValue:(failed + finished) / total];
    else
        [progressBar setDoubleValue:0.0];

    // Create the label string
    var labelString = finished + "/" + total;
    
    // Add active/failed info if relevant
    if (active > 0) labelString += " [" + active + " run]";
    if (failed > 0) labelString += " (" + failed + " err)";

    [statsLabel setStringValue:labelString];

    // Color logic
    if (failed > 0) {
        [statsLabel setTextColor:[CPColor redColor]];
    } else if (active > 0) {
        [statsLabel setTextColor:[CPColor blueColor]];
    } else if (finished == total && total > 0) {
        [statsLabel setTextColor:[CPColor colorWithCalibratedRed:0.0 green:0.5 blue:0.0 alpha:1.0]];
    } else {
        [statsLabel setTextColor:[CPColor blackColor]];
    }
}
@end

@implementation FSArrayController(baseReloadFix)

- (void)fullyReloadAsync
{
    var entity = self._entity;
    entity._pkcache = [];
    [entity._store fetchObjectsForURLRequest:[entity._store requestForAddressingAllObjectsInEntity:entity] inEntity:entity requestDelegate:self._contentObject];
}

@end

@implementation CGPTURLRequest : CPURLRequest

- (id)initWithURL:(CPURL)anURL cachePolicy:(CPURLRequestCachePolicy)aCachePolicy timeoutInterval:(CPTimeInterval)aTimeoutInterval
{
    if (self = [super initWithURL:anURL initWithURL:anURL cachePolicy:aCachePolicy timeoutInterval:aTimeoutInterval])
    {
        [self setValue:"3037" forHTTPHeaderField:"X-ARGOS-ROUTING"];
    }

    return self;
}

@end

@implementation SessionStore : FSStore

- (CPURLRequest)requestForAddressingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{
    var request = [CGPTURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/"+someval];

    return request;
}
-(CPURLRequest) requestForInsertingObjectInEntity:(FSEntity) someEntity
{
    var request = [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+ [someEntity pk]];
    [request setHTTPMethod:"POST"];

    return request;
}

- (CPURLRequest)requestForFuzzilyAddressingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{
    var request = [CGPTURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/like/"+someval];

    return request;
}

- (CPURLRequest)requestForAddressingAllObjectsInEntity:(FSEntity) someEntity
{
    var request = [CGPTURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name] ];

    return request;
}

@end

@implementation AppController : CPObject
{
    id  store @accessors;

    id  mainWindow;
    id  addBlocksWindow;
    id  editWindow;
    id  laceView;
    id  inputWindow;
    id  inputText;
    id  projectImportExportWindow;
    id  importFromUploadWindow;
    id  projectJSON;

    id  laceViewController;
    id  projectsController
    id  inputController
    id  outputController
    id  blocksCatalogueController @accessors;
    id  blocksController @accessors;
    id  settingsController @accessors;
    id  globalsController @accessors;
    id  blocksVersionsController @accessors;
    id  blockIndex;
    id  connections;
    id  addBlocksPopover;
    id  editPopover;
    id  runConnection;
    id  spinnerImg;


    id embeddingModelsController;
    id embeddedDatasetsController;
    id embeddedDataController;
    id importCSVText;

    id  _searchTerm @accessors(property=searchTerm);
    id  _playgroundSearchTerm @accessors(property=playgroundSearchTerm);
    id  playgroundTV;

    // Upload properties
    id myCuploader;
    id queueController;

    int importPromptID;

    CPPanel         jobsPanel;
    CPTableView     jobsTable;
    CPArray         jobsData;
    CPTimer         jobsPollingTimer;

    CPTextView sqlInputView;
    CPTextView sqlOutputView;
}

- (void)initJobsPanel
{
    if (jobsPanel)
    {
        [jobsPanel makeKeyAndOrderFront:self];
        [self startJobsPolling];
        return;
    }

    // 1. Create Panel (Same as before)
    jobsPanel = [[CPPanel alloc] initWithContentRect:CGRectMake(100, 100, 500, 300) styleMask:CPHUDBackgroundWindowMask | CPClosableWindowMask | CPResizableWindowMask | CPTitledWindowMask];
    [jobsPanel setTitle:@"Batch Progress (Daily)"];
    [jobsPanel setFloatingPanel:YES];
    [jobsPanel setDelegate:self];

    var contentView = [jobsPanel contentView];

    // 2. ScrollView (Same as before)
    var scrollView = [[CPScrollView alloc] initWithFrame:CGRectInset([contentView bounds], 10, 10)];
    [scrollView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    
    // 3. TableView
    jobsTable = [[CPTableView alloc] initWithFrame:[scrollView bounds]];
    [jobsTable setDataSource:self];
    [jobsTable setDelegate:self];
    [jobsTable setUsesAlternatingRowBackgroundColors:YES];
    [jobsTable setRowHeight:26.0];

    // --- NEW COLUMNS ---

    // Column 1: Date
    var dateColumn = [[CPTableColumn alloc] initWithIdentifier:@"date"];
    [[dateColumn headerView] setStringValue:@"Date"];
    [dateColumn setWidth:100.0];
    [jobsTable addTableColumn:dateColumn];

    // Column 2: Progress (Custom View)
    var progressColumn = [[CPTableColumn alloc] initWithIdentifier:@"progress"];
    [[progressColumn headerView] setStringValue:@"Progress (Finished/Total)"];
    [progressColumn setWidth:350.0]; // Wider for the bar
    
    // Use the new DailyProgressView
    var progressProto = [[DailyProgressView alloc] initWithFrame:CGRectMake(0,0,350,26)];
    [progressColumn setDataView:progressProto];
    
    [jobsTable addTableColumn:progressColumn];

    [scrollView setDocumentView:jobsTable];
    [contentView addSubview:scrollView];

    [jobsPanel makeKeyAndOrderFront:self];
    [self startJobsPolling];
}

// this is just to force the prompts popup items in the playground such in case a new prompt is added and the user wants to test it immediately
- (void)tabView:(CPTabView)aTabView willSelectTabViewItem:(CPTabViewItem)aTabViewItem
{

    if ([aTabViewItem label] == "Playground" && playgroundTV)
    {
        // force reload data from the store
        var entity = projectsController._entity;
        entity._pkcache = [];
        [projectsController setContent:[entity allObjects]];

        // refresh archived data in the tableview column
        var promptColumn = [playgroundTV tableColumnWithIdentifier:"idprompt"];
        var prototypeButton = [promptColumn dataView];
        [promptColumn setDataView:nil];
        [promptColumn setDataView:prototypeButton];

        // remove stale views from the screen
        for (var row in playgroundTV._dataViewsForRows) {
            if (playgroundTV._dataViewsForRows.hasOwnProperty(row)) {
                var columnsForRow = playgroundTV._dataViewsForRows[row];
                for (var columnUID in columnsForRow) {
                    if (columnsForRow.hasOwnProperty(columnUID)) {
                        var view = columnsForRow[columnUID];
                        [view removeFromSuperview];
                    }
                }
            }
        }

        // nuke private caches
        playgroundTV._cachedDataViews = {};
        playgroundTV._dataViewsForRows = {};
        // redraw
        [playgroundTV reloadData];
    }
}

- (void)flushGUI
{
    var fr = [[CPApp keyWindow] firstResponder];

    if ([fr respondsToSelector:@selector(_reverseSetBinding)])
        [fr _reverseSetBinding]; // flush any typed text before printing


    if ([fr isKindOfClass:CPDatePicker])
        [fr resignFirstResponder]; // important for the textual datepicker to work properly
}

- (void)setSearchTerm:(id)aTerm
{
    if (aTerm && aTerm.length)
        [embeddedDataController setFilterPredicate:[CPPredicate predicateWithFormat:"payload CONTAINS[cd] %@ or label = %@", aTerm, aTerm]];
    else
        [embeddedDataController setFilterPredicate:nil];
}

- (void)setPlaygroundSearchTerm:(id)aTerm
{
    if (aTerm && aTerm.length)
        [inputController setFilterPredicate:[CPPredicate predicateWithFormat:"content CONTAINS[cd] %@ or title CONTAINS[cd] %@", aTerm, aTerm]];
    else
        [inputController setFilterPredicate:nil];
}

-(void)setButtonBusy:(CPButton)myButton
{
    myButton._oldImage = [myButton image];
    [myButton setImage:spinnerImg];
    [myButton setValue:spinnerImg forThemeAttribute:@"image" inState:CPThemeStateDisabled];
    [myButton setEnabled:NO];
}
-(void)resetButtonBusy:(CPButton)myButton
{
    [myButton setImage:myButton._oldImage];
    [myButton setEnabled:YES];
}

- (void)performImportCSV:(id)sender suffix:(CPString)suffix
{
    var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/import_embedding_dataset/" + [embeddedDatasetsController valueForKeyPath:"selection.id"] + suffix];
    [myreq setHTTPMethod:"POST"];
    [myreq setHTTPBody:[importCSVText stringValue]];
    [CPURLConnection connectionWithRequest:myreq delegate:nil];

    [importCSVText setString:'']; // fixme: better gui feedback
}

- (void)performImportCSV:(id)sender
{
    [self performImportCSV:sender suffix:""];
}

- (void)performImportCSVAppend:(id)sender
{
    [self performImportCSV:sender suffix:"?preserve=1"];
}

- (void)performImportCSVRemove:(id)sender
{
    [self performImportCSV:sender suffix:"?remove=1"];
}

-(void)openWindowWithURL:(CPString)myURL inWindowID:(CPString)myid
{
    // window.removeEventListener('beforeunload', beforeUnloadHandler);
    window.open(myURL, myid);
    // window.addEventListener('beforeunload', beforeUnloadHandler);
}

- (void)patchbayHandbuch:(id)sender
{
    [self openWindowWithURL:"http://aug-info:4567/PatchbayManual.md"  inWindowID:'patchbay_manual_window'];
}

- (void)downloadDataset:(id)sender
{
    [self openWindowWithURL:BaseURL + 'LLM/get_data_from_dataset/' + [embeddedDatasetsController valueForKeyPath:'selection.name'] inWindowID:'download_window'];
}

- (void)duplicatePrompt:(id)sender
{
    var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/duplicate_prompt/" + [projectsController valueForKeyPath:"selection.id"]];
    [myreq setHTTPMethod:"POST"];
    var connection = [CPURLConnection connectionWithRequest:myreq delegate:self];
    [self setButtonBusy:sender];
    connection._senderButton = sender;
}

- (void)run:(id)sender
{
    [self flushGUI];

    setTimeout(function(){

        var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/run/" + [inputController valueForKeyPath:"selection.id"]
                                     cachePolicy:CPURLRequestReloadIgnoringLocalCacheData timeoutInterval:5000000];
        [myreq setHTTPMethod:"POST"];
        runConnection = [CPURLConnection connectionWithRequest:myreq delegate:self];

        [self setButtonBusy:sender]
        runConnection._senderButton = sender;
    }, 250);
}

- (void)showImportExportWindow:(id)sender
{
    [projectImportExportWindow makeKeyAndOrderFront:sender];
}

- (void)exportProject:(id)sender
{
    var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/project/export/" + [projectsController valueForKeyPath:"selection.id"]];
    var connection = [CPURLConnection connectionWithRequest:myreq delegate:self];
    [self setButtonBusy:sender];
    connection._senderButton = sender;
    connection.isExport = YES;
}

- (void)importProject:(id)sender
{
    var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/project/import"];
    [myreq setHTTPMethod:"POST"];
    [myreq setHTTPBody:[projectJSON stringValue]];
    var connection = [CPURLConnection connectionWithRequest:myreq delegate:self];
    [self setButtonBusy:sender];
    connection._senderButton = sender;
}

- (void)importFromUpload:(id)sender
{
    [importFromUploadWindow makeKeyAndOrderFront:sender];
}

- (void)performImportFromUpload:(id)sender
{
    document.title = importPromptID;

    var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/import_from_upload/" + importPromptID];
    [myreq setHTTPMethod:"POST"];
    [myreq setHTTPBody:''];
    [CPURLConnection connectionWithRequest:myreq delegate:self];

    [importFromUploadWindow orderOut:sender];
}

- (void)cancelImportFromUpload:(id)sender
{
    [importFromUploadWindow orderOut:sender];
}


- (void)insertInput:(id)sender
{
    [inputController insert:sender]
    [inputWindow makeKeyAndOrderFront:sender]
    [inputText selectAll:sender]
}

- (void)removeInput:(id)sender
{
    [inputController remove:sender]
}

- (void)downloadCSV:(id)sender
{
    [self openWindowWithURL:BaseURL + 'LLM/download_csv' inWindowID:'download_csv_window'];
}

- (void)batchRunAll:(id)sender
{
    var myalert = [CPAlert new];
    [myalert setMessageText: "Start batch process for all inputs?"];
    [myalert setInformativeText: "This will enqueue a job for every item in the input list and may take a long time to complete."];
    [myalert addButtonWithTitle:"Cancel"];
    [myalert addButtonWithTitle:"Start Batch"];
    [myalert beginSheetModalForWindow:mainWindow modalDelegate:self didEndSelector:@selector(batchRunAllWarningDidEnd:code:context:) contextInfo:sender];
}

- (void)batchRunAllWarningDidEnd:(CPAlert)anAlert code:(id)code context:(id)sender
{
    if (code) // User clicked "Start Batch"
    {
        var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/batch_process"];
        [myreq setHTTPMethod:"POST"];
        var connection = [CPURLConnection connectionWithRequest:myreq delegate:self];

        if ([sender isKindOfClass:CPButton]) {
            [self setButtonBusy:sender];
            connection._senderButton = sender;
        }
    }
}

- (void)deleteAllInputs:(id)sender
{
    var myalert = [CPAlert new];
    [myalert setMessageText: "Are you sure you want to delete all inputs?"];
    [myalert setInformativeText: "This action cannot be undone."];
    [myalert addButtonWithTitle:"Keep Inputs"];
    [myalert addButtonWithTitle:"Delete All"];
    [myalert beginSheetModalForWindow:mainWindow modalDelegate:self didEndSelector:@selector(deleteAllInputsWarningDidEnd:code:context:) contextInfo:sender];
}

- (void)deleteAllInputsWarningDidEnd:(CPAlert)anAlert code:(id)code context:(id)sender
{
    if (code) // User clicked "Delete All"
    {
        var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/delete_all_inputs"];
        [myreq setHTTPMethod:"DELETE"];
        var connection = [CPURLConnection connectionWithRequest:myreq delegate:self];

        if ([sender isKindOfClass:CPButton]) {
            [self setButtonBusy:sender];
            connection._senderButton = sender;
        }
    }
}

- (void)removeBlocks:(id)sender
{
    [laceViewController removeBlocks:sender]
}

- (void)addBlocks:(id)sender
{
    [laceViewController addBlocks:sender]
}

- (void)performAddBlocks:(id)sender
{
    [laceViewController performAddBlocks:sender]
}

- (void)connection:(CPConnection)someConnection didReceiveData:(CPData)data
{
    if (someConnection._senderButton && [someConnection._senderButton isKindOfClass:CPButton])
        [self resetButtonBusy:someConnection._senderButton];

    if (someConnection.isSQL)
    {
        var resultString = data; // CPData behaves like string in many contexts here
        try {
            // Parse JSON to pretty-print it
            var json = JSON.parse(resultString);
            var prettyJson = JSON.stringify(json, null, 4);
            [sqlOutputView setString:prettyJson];
        } catch (e) {
            // If raw text or error
            [sqlOutputView setString:resultString];
        }
        return;
   }

   if (someConnection.isJobStatus)
   {
        // Simple JSON parse
        try {
             jobsData = JSON.parse(data);
             [jobsTable reloadData];
        }
        catch (e)
        {
            CPLog("Error parsing job status: " + e);
        }

       return;
    }

    var urlString = [[[someConnection currentRequest] URL] absoluteString];

    if (urlString.indexOf(BaseURL + "LLM/delete_all_inputs") >= 0)
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:@"Success" message:@"All inputs have been deleted." customIcon:TNGrowlIconInfo];
        // Use the fixed method to perform a full reload of the controller's content

        var entity = inputController._entity;
        entity._pkcache = [];
        [inputController setContent:[entity allObjects]];

        [outputController reload]; // Also clear the output view
        return;
    }

    if (urlString.indexOf(BaseURL + "LLM/batch_process") >= 0)
    {
        var result = JSON.parse(data);
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:@"Batch Process Started" message:result['message'] customIcon:TNGrowlIconInfo];
        return;
    }

    if (urlString.indexOf(BaseURL + "LLM/import_from_upload/") >= 0)
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:@"Import from upload" message:data customIcon:TNGrowlIconInfo];

        var entity = inputController._entity;
        entity._pkcache = [];
        [inputController setContent:[entity allObjects]];

        return;
    }

    if (someConnection.isExport)
    {
        var responseString = data;
        var responseObject = JSON.parse(responseString);
        var prettyJSON = JSON.stringify(responseObject, null, 4); // 4 spaces for indentation
        [projectJSON setString:prettyJSON];
        [projectImportExportWindow makeKeyAndOrderFront:nil];
        return;
    }

    if (urlString.indexOf(BaseURL + "LLM/project/import") >= 0)
    {
        var entity = projectsController._entity;
        entity._pkcache = [];
        [projectsController setContent:[entity allObjects]];

        [projectImportExportWindow orderOut:nil];
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:@"Success" message:@"Project imported." customIcon:TNGrowlIconInfo];
        return;
    }

    if (urlString.indexOf(BaseURL + "LLM/duplicate_prompt/") >= 0)
    {
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:@"Success" message:@"Prompt duplicated." customIcon:TNGrowlIconInfo];
        [projectsController reload];
        return;
    }

    [outputController reload];
}

- (void)cup:(Cup)aCup uploadDidCompleteForFile:(CupFile)aFile
{
    // remove from list
    var indexes = [aCup.queue indexesOfObjectsPassingTest:function(file)
                   {
        return  file === aFile;
    }];
    [aCup.queue removeObjectsAtIndexes:indexes];
    [[aCup queueController] setContent:aCup.queue];
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    store = [[SessionStore alloc] initWithBaseURL:HostURL+"/LLM"];

    [CPBundle loadRessourceNamed:"model.gsmarkup" owner:self];
    [CPBundle loadRessourceNamed:"gui.gsmarkup" owner:self];
    spinnerImg = [[CPImage alloc] initWithContentsOfFile:[CPString stringWithFormat:@"%@%@", [[CPBundle mainBundle] resourcePath], "spinner.gif"]];

    // Initialize Uploader
    myCuploader = [[Cup alloc] initWithURL:BaseURL + "LLM/upload"];
    queueController = [myCuploader queueController];
    [myCuploader setDropTarget:playgroundTV];
    [myCuploader setAutoUpload:YES];
    [myCuploader setRemoveCompletedFiles:YES];
    [myCuploader setDelegate:self];

    [[TNGrowlCenter defaultCenter] setView:[[CPApp mainWindow] contentView]];
    [[TNGrowlCenter defaultCenter] setLifeDefaultTime:10];

    [[mainWindow contentView] setBackgroundColor:[CPColor colorWithWhite:0.95 alpha:1.0]];

    laceViewController = [LaceViewController new];
    [laceViewController setView:laceView];
    [laceViewController setBlocksController:blocksController];
    [laceViewController setSettingsController:settingsController];
    [laceViewController setEditWindow:editWindow];
    [laceViewController setAddBlocksView:[addBlocksWindow contentView]];

    [self showJobsMonitor:self];
}

// Button Action to show the panel
- (void)showJobsMonitor:(id)sender
{
    [self initJobsPanel];
}

// --- Polling Logic ---

- (void)startJobsPolling
{
    if (!jobsPollingTimer || ![jobsPollingTimer isValid])
    {
        [self fetchJobsStatus]; // Fetch immediately
        jobsPollingTimer = [CPTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(fetchJobsStatus) userInfo:nil repeats:YES];
    }
}

- (void)stopJobsPolling
{
    if (jobsPollingTimer)
    {
        [jobsPollingTimer invalidate];
        jobsPollingTimer = nil;
    }
}

// Window Delegate to stop polling when closed
- (void)windowWillClose:(CPNotification)aNotification
{
    if ([aNotification object] === jobsPanel)
    {
        [self stopJobsPolling];
    }
}

// --- Data Fetching ---

- (void)fetchJobsStatus
{
    var request = [CPURLRequest requestWithURL:BaseURL + "LLM/minion/status"];
    [request setHTTPMethod:"GET"];
    var conn = [CPURLConnection connectionWithRequest:request delegate:self];
    conn.isJobStatus = YES; // Mark connection to identify it in callback
}

- (int)numberOfRowsInTableView:(CPTableView)aTableView
{
    if (aTableView === jobsTable) return [jobsData count];
    return 0;
}

- (id)tableView:(CPTableView)aTableView objectValueForTableColumn:(CPTableColumn)aColumn row:(int)rowIndex
{
    if (aTableView === jobsTable)
    {
        var item = jobsData[rowIndex];
        
        if ([[aColumn identifier] isEqualToString:@"date"]) 
        {
            // The backend sends YYYY-MM-DD string, usually acceptable as is.
            return item.date;
        }

        // Pass the whole item object to the custom view so it can extract total/finished/etc
        if ([[aColumn identifier] isEqualToString:@"progress"])
            return item;
    }
    return nil;
}

- (void)runSQL:(id)sender
{
    var sql = [sqlInputView string];
    
    if (!sql || sql.length === 0) {
        alert("Please enter a SQL query.");
        return;
    }

    [sqlOutputView setString:"Executing..."];

    var myreq = [CPURLRequest requestWithURL:BaseURL + "LLM/run_raw_sql"];
    [myreq setHTTPMethod:"POST"];
    [myreq setHTTPBody:sql];
    
    var connection = [CPURLConnection connectionWithRequest:myreq delegate:self];
    
    // Tag this connection so we know how to handle the response
    connection.isSQL = YES; 
    
    [self setButtonBusy:sender];
    connection._senderButton = sender;
}

- (void)downloadSQL:(id)sender
{
    var sql = [sqlInputView string];
    
    if (!sql || sql.length === 0) {
        alert("Please enter a SQL query.");
        return;
    }

    // Create a hidden HTML form to submit the POST request for download
    var form = document.createElement("form");
    form.method = "POST";
    form.action = BaseURL + "LLM/run_sql_csv";
    form.style.display = "none";
    form.target = "_blank"; // Optional: Ensures download doesn't block UI if server hangs

    // Add the SQL as a textarea input (handles newlines/quotes better than input type=text)
    var input = document.createElement("textarea");
    input.name = "sql";
    input.value = sql;
    form.appendChild(input);

    document.body.appendChild(form);
    
    form.submit();
    
    // Clean up
    document.body.removeChild(form);
}

@end
