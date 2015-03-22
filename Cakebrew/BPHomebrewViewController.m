//
//	HomebrewController.m
//	Cakebrew – The Homebrew GUI App for OS X
//
//	Created by Vincent Saluzzo on 06/12/11.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "BPHomebrewViewController.h"
#import "BPFormula.h"
#import "BPHomebrewManager.h"
#import "BPHomebrewInterface.h"
#import "BPFormulaOptionsWindowController.h"
#import "BPInstallationWindowController.h"
#import "BPUpdateViewController.h"
#import "BPDoctorViewController.h"
#import "BPFormulaeDataSource.h"
#import "BPSelectedFormulaViewController.h"

typedef NS_ENUM(NSUInteger, HomeBrewTab) {
	HomeBrewTabFormulae,
	HomeBrewTabDoctor,
	HomeBrewTabUpdate
};

@interface BPHomebrewViewController () <NSTableViewDelegate, BPSideBarControllerDelegate, BPHomebrewManagerDelegate, NSMenuDelegate>

@property (weak)			 BPAppDelegate	  *appDelegate;

@property NSInteger lastSelectedSidebarIndex;

@property BOOL isSearching;
@property BPWindowOperation toolbarButtonOperation;


@property (strong, nonatomic) BPFormulaeDataSource *formulaeDataSource;
@property (strong, nonatomic) BPFormulaOptionsWindowController *formulaOptionsWindowController;
@property (strong, nonatomic) BPInstallationWindowController *operationWindowController;
@property (strong, nonatomic) BPUpdateViewController *updateViewController;
@property (strong, nonatomic) BPDoctorViewController *doctorViewController;
@property (strong, nonatomic) BPFormulaPopoverViewController *formulaPopoverViewController;
@property (weak, nonatomic) IBOutlet BPSelectedFormulaViewController *selectedFormulaeViewController;

@end

@implementation BPHomebrewViewController
{
	BPHomebrewManager			   *_homebrewManager;
}

- (BPFormulaPopoverViewController *)formulaPopoverViewController
{
	if (!_formulaPopoverViewController) {
		_formulaPopoverViewController = [[BPFormulaPopoverViewController alloc] init];
		//this will force initialize controller with its view
		__unused NSView *view = _formulaPopoverViewController.view;
	}
	return _formulaPopoverViewController;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		_homebrewManager = [BPHomebrewManager sharedManager];
		[_homebrewManager setDelegate:self];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lockWindow) name:kBP_NOTIFICATION_LOCK_WINDOW object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(unlockWindow) name:kBP_NOTIFICATION_UNLOCK_WINDOW object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchUpdatedNotification:) name:kBP_NOTIFICATION_SEARCH_UPDATED object:nil];
	}
	return self;
}

- (void)awakeFromNib
{
	self.formulaeDataSource = [[BPFormulaeDataSource alloc] initWithMode:kBPListAll];
	self.tableView_formulae.dataSource = self.formulaeDataSource;
	self.tableView_formulae.delegate = self;

	//Creating view for update tab
	self.updateViewController = [[BPUpdateViewController alloc] initWithNibName:nil bundle:nil];
	NSView *updateView = [self.updateViewController view];
	if ([[self.tabView tabViewItems] count] > HomeBrewTabUpdate) {
		NSTabViewItem *updateTab = [self.tabView tabViewItemAtIndex:HomeBrewTabUpdate];
		[updateTab setView:updateView];
	}

	//Creating view for doctor tab
	self.doctorViewController = [[BPDoctorViewController alloc] initWithNibName:nil bundle:nil];
	NSView *doctorView = [self.doctorViewController view];
	if ([[self.tabView tabViewItems] count] > HomeBrewTabDoctor) {
		NSTabViewItem *doctorTab = [self.tabView tabViewItemAtIndex:HomeBrewTabDoctor];
		[doctorTab setView:doctorView];
	}

	[self.splitView setMinSize:165.f ofSubviewAtIndex:0];
	[self.splitView setMinSize:400.f ofSubviewAtIndex:1];
	[self.splitView setDividerColor:kBPSidebarDividerColor];
	[self.splitView setDividerThickness:0];

	[self.view_disablerLock setShouldDrawBackground:YES];

	[self.sidebarController refreshSidebarBadges];

	[self.outlineView_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemInstalled] byExtendingSelection:NO];

	_appDelegate = BPAppDelegateRef;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kBP_NOTIFICATION_LOCK_WINDOW object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kBP_NOTIFICATION_UNLOCK_WINDOW object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kBP_NOTIFICATION_SEARCH_UPDATED object:nil];
	[_homebrewManager setDelegate:nil];
}

- (void)prepareFormulae:(NSArray*)formulae forOperation:(BPWindowOperation)operation withOptions:(NSArray*)options
{
	self.operationWindowController = [BPInstallationWindowController runWithOperation:operation
																			 formulae:formulae
																			  options:options];
}

- (void)lockWindow
{
	[self.view_disablerLock setHidden:NO];
	[self.view_disablerLock setWantsLayer:YES];
	[self.label_information setHidden:YES];
	[self.splitView setHidden:YES];

	[self.toolbar.items enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([obj respondsToSelector:@selector(setEnabled:)]) {
			[obj setEnabled:NO];
		}
	}];

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Error!"];
	[alert setInformativeText:@"Homebrew was not found in your system. Please install Homebrew before using Cakebrew. You can click the button below to open Homebrew's website."];
	[alert setShowsSuppressionButton:NO];
	[alert setShowsHelp:NO];
	[alert addButtonWithTitle:@"Homebrew Website"];
	[alert addButtonWithTitle:@"Cancel"];

	[alert.window setTitle:@"Cakebrew"];

	if ([alert respondsToSelector:@selector(beginSheetModalForWindow:completionHandler:)]) {
		[alert beginSheetModalForWindow:_appDelegate.window completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == 1000) {
				[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brew.sh"]];
			}
		}];
	} else {
		[[NSApplication sharedApplication] beginSheet:alert.window modalForWindow:_appDelegate.window modalDelegate:self didEndSelector:@selector(openBrewWebsiteSheetDidEnd:returnCode:contextInfo:) contextInfo:nil];
	}
}

- (void)openBrewWebsiteSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
	if (returnCode == NSAlertDefaultReturn) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brew.sh"]];
	}
}

- (void)unlockWindow
{
	[self.view_disablerLock setHidden:YES];
	[self.label_information setHidden:NO];
	[self.splitView setHidden:NO];

	[self.toolbar.items enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([obj respondsToSelector:@selector(setEnabled:)]) {
			[obj setEnabled:YES];
		}
	}];

	[[BPHomebrewManager sharedManager] updateRebuildingCache:YES];
}

- (void)updateInterfaceItems
{
	NSInteger selectedTab = [self.outlineView_sidebar selectedRow];
	NSInteger selectedIndex = [self.tableView_formulae selectedRow];
	NSIndexSet *selectedRows = [self.tableView_formulae selectedRowIndexes];
	NSArray *selectedFormulae = [self.formulaeDataSource formulasAtIndexSet:selectedRows];
	if ([selectedFormulae count] == 1) {
		[self setCurrentFormula:[selectedFormulae firstObject]];
	}
	[self.selectedFormulaeViewController setFormulae:selectedFormulae];
	[self.selectedFormulaeViewController.view setHidden:NO];

	if (selectedTab == FormulaeSideBarItemRepositories) { // Repositories sidebaritem
		[self.toolbarButton_installUninstall setEnabled:YES];
		[self.toolbarButton_formulaInfo setEnabled:NO];
		[self.selectedFormulaeViewController.view setHidden:YES];

		if (selectedIndex != -1) {
			[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"delete.icns"]];
			[self.toolbarButton_installUninstall setLabel:@"Untap Repository"];
			[self setToolbarButtonOperation:kBPWindowOperationUntap];
		} else {
			[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"download.icns"]];
			[self.toolbarButton_installUninstall setLabel:@"Tap Repository"];
			[self setToolbarButtonOperation:kBPWindowOperationTap];
		}
	}
	else if (selectedIndex == -1 || selectedTab > FormulaeSideBarItemToolsCategory)
	{
		[self.toolbarButton_installUninstall setEnabled:NO];
		[self.toolbarButton_formulaInfo setEnabled:NO];
	}
	else if ([[self.tableView_formulae selectedRowIndexes] count] > 1)
	{
		[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"reload.icns"]];
		[self.toolbarButton_installUninstall setLabel:@"Update Selected"];
		[self setToolbarButtonOperation:kBPWindowOperationUpgrade];
	}
	else
	{
		BPFormula *formula = [self.formulaeDataSource formulaAtIndex:selectedIndex];

		[self.toolbarButton_installUninstall setEnabled:YES];
		[self.toolbarButton_formulaInfo setEnabled:YES];

		switch ([[BPHomebrewManager sharedManager] statusForFormula:formula]) {
			case kBPFormulaInstalled:
				[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"delete.icns"]];
				[self.toolbarButton_installUninstall setLabel:@"Uninstall Formula"];
				[self setToolbarButtonOperation:kBPWindowOperationUninstall];
				break;

			case kBPFormulaOutdated:
				if ([self.outlineView_sidebar selectedRow] == FormulaeSideBarItemOutdated) {
					[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"reload.icns"]];
					[self.toolbarButton_installUninstall setLabel:@"Update Formula"];
					[self setToolbarButtonOperation:kBPWindowOperationUpgrade];
				} else {
					[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"delete.icns"]];
					[self.toolbarButton_installUninstall setLabel:@"Uninstall Formula"];
					[self setToolbarButtonOperation:kBPWindowOperationUninstall];
				}
				break;

			case kBPFormulaNotInstalled:
				[self.toolbarButton_installUninstall setImage:[NSImage imageNamed:@"download.icns"]];
				[self.toolbarButton_installUninstall setLabel:@"Install Formula"];
				[self setToolbarButtonOperation:kBPWindowOperationInstall];
				break;
		}
	}
}

- (void)searchUpdatedNotification:(NSNotification*)notification
{
	_isSearching = YES;
	if ([self.outlineView_sidebar selectedRow] != FormulaeSideBarItemOutdated)
		[self.outlineView_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemAll] byExtendingSelection:NO];

	[self configureTableForListing:kBPListSearch];
}

- (void)configureTableForListing:(BPListMode)mode
{
	[self.tableView_formulae deselectAll:nil];
	[self.tableView_formulae setMode:mode];
	[self.formulaeDataSource setMode:mode];
	[self.tableView_formulae reloadData];
	[self updateInterfaceItems];
}

#pragma mark - Homebrew Manager Delegate

- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager
{
	[[self.tableView_formulae menu] cancelTracking];
	self.currentFormula = nil;
	self.selectedFormulaeViewController.formulae = nil;
	[self.formulaeDataSource refreshBackingArray];
	[self.sidebarController refreshSidebarBadges];

	// Used after unlocking the app when inserting custom homebrew installation path
	BOOL shouldReselectFirstRow = ([_outlineView_sidebar selectedRow] < 0);

	[self.outlineView_sidebar reloadData];

	[self setEnableUpgradeFormulasMenu:([[BPHomebrewManager sharedManager] formulae_outdated].count > 0)];

	if (shouldReselectFirstRow)
		[_outlineView_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:FormulaeSideBarItemInstalled] byExtendingSelection:NO];
	else
		[_outlineView_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_lastSelectedSidebarIndex] byExtendingSelection:NO];
}

#pragma mark - NSTableView Delegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	[self updateInterfaceItems];
}

#pragma mark - BPSideBarDelegate Delegate

- (void)sourceListSelectionDidChange
{
	NSString *message;
	NSUInteger tabIndex = 0;

	if ([self.outlineView_sidebar selectedRow] >= 0)
		_lastSelectedSidebarIndex = [self.outlineView_sidebar selectedRow];

	[self updateInterfaceItems];

	switch ([self.outlineView_sidebar selectedRow]) {
		case FormulaeSideBarItemInstalled: // Installed Formulae
			[self configureTableForListing:kBPListInstalled];
			message = @"These are the formulae already installed in your system.";
			break;

		case FormulaeSideBarItemOutdated: // Outdated Formulae
			[self configureTableForListing:kBPListOutdated];
			message = @"These formulae are already installed, but have an update available.";
			break;

		case FormulaeSideBarItemAll: // All Formulae
			[self configureTableForListing:kBPListAll];
			message = @"These are all the formulae available for installation with Homebrew.";
			break;

		case FormulaeSideBarItemLeaves:	// Leaves
			[self configureTableForListing:kBPListLeaves];
			message = @"These formulae are not dependencies of any other formulae.";
			break;

		case FormulaeSideBarItemRepositories: // Repositories
			[self configureTableForListing:kBPListRepositories];
			message = @"These are the repositories you have tapped.";
			break;

		case FormulaeSideBarItemDoctor: // Doctor
			message = @"The doctor is a Homebrew feature that detects the most common causes of errors.";
			tabIndex = HomeBrewTabDoctor;
			break;

		case FormulaeSideBarItemUpdate: // Update Tool
			message = @"Updating Homebrew means fetching the latest info about the available formulae.";
			tabIndex = HomeBrewTabUpdate;
			break;

		default:
			break;
	}

	if (message) [self.label_information setStringValue:message];
	[self.tabView selectTabViewItemAtIndex:tabIndex];
}

#pragma mark - NSMenu Delegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	[self.tableView_formulae selectRowIndexes:[NSIndexSet indexSetWithIndex:[self.tableView_formulae clickedRow]] byExtendingSelection:NO];
}

#pragma mark - IBActions

- (IBAction)showFormulaInfo:(id)sender
{
	NSPopover *popover = self.formulaPopoverViewController.formulaPopover;
	if ([popover isShown]) {
		[popover close];
	}
	NSInteger selectedIndex = [self.tableView_formulae selectedRow];
	BPFormula *formula = [self.formulaeDataSource formulaAtIndex:selectedIndex];
	[self.formulaPopoverViewController setFormula:formula];

	NSRect anchorRect = [self.tableView_formulae rectOfRow:selectedIndex];
	anchorRect.origin = [self.scrollView_formulae convertPoint:anchorRect.origin fromView:self.tableView_formulae];

	[popover showRelativeToRect:anchorRect
						 ofView:self.scrollView_formulae
				  preferredEdge:NSMaxXEdge];
}

- (IBAction)installUninstallUpdate:(id)sender {
	// Check if there is a background task running. It is not smart to run two different Homebrew tasks at the same time!
	if (_appDelegate.isRunningBackgroundTask)
	{
		[_appDelegate displayBackgroundWarning];
		return;
	}
	[_appDelegate setRunningBackgroundTask:YES];

	NSInteger selectedIndex = [self.tableView_formulae selectedRow];
	NSInteger selectedTab = [self.outlineView_sidebar selectedRow];
	BPFormula *formula = [self.formulaeDataSource formulaAtIndex:selectedIndex];

	if (formula) {
		NSString *message;
		void (^operationBlock)(void);

		switch (_toolbarButtonOperation) {
			case kBPWindowOperationInstall:
			{
				message = @"Are you sure you want to install the formula '%@'?";
				operationBlock = ^{
					[self prepareFormulae:@[formula] forOperation:kBPWindowOperationInstall withOptions:nil];
				};
			}
				break;

			case kBPWindowOperationUninstall:
			{
				message = @"Are you sure you want to uninstall the formula '%@'?";
				operationBlock = ^{
					[self prepareFormulae:@[formula] forOperation:kBPWindowOperationUninstall withOptions:nil];
				};
			}
				break;

			case kBPWindowOperationUpgrade:
			{
				message = @"Are you sure you want to upgrade the selected formuale?";
				NSIndexSet *indexes = [self.tableView_formulae selectedRowIndexes];
				NSArray *formulae = [self.formulaeDataSource formulasAtIndexSet:indexes];

				operationBlock = ^{
					[self prepareFormulae:formulae forOperation:kBPWindowOperationUpgrade withOptions:nil];
				};
			}
				break;

			case kBPWindowOperationUntap:
			{
				message = @"Are you sure you want to untap the repository '%@'?";
				operationBlock = ^{
					[self prepareFormulae:@[formula] forOperation:kBPWindowOperationUntap withOptions:nil];
				};
			}
        break;

			case kBPWindowOperationTap:
			{
				message = @"Are you sure you want to tap the repository '%@'?";
				operationBlock = ^{
					[self prepareFormulae:@[formula] forOperation:kBPWindowOperationTap withOptions:nil];
				};
			}
				break;
		}

		if (message) {
			NSAlert *alert = [NSAlert alertWithMessageText:@"Attention!" defaultButton:@"Yes" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:message, formula.name];
			[alert.window setTitle:@"Cakebrew"];

			NSInteger returnValue = [alert runModal];
			if (returnValue == NSAlertDefaultReturn) {
				operationBlock();
			}
			else {
				[_appDelegate setRunningBackgroundTask:NO];
			}
		} else {
			operationBlock();
		}
	}
	else if (selectedTab == FormulaeSideBarItemRepositories && _toolbarButtonOperation == kBPWindowOperationTap)
	{
		NSAlert *alert = [NSAlert alertWithMessageText:@"Attention!" defaultButton:@"OK" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"What repository would you like to tap?"];
		[alert.window setTitle:@"Cakebrew"];

		NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,200,24)];
		[input setStringValue:@""];
		[alert setAccessoryView:input];

		NSInteger returnValue = [alert runModal];
		if (returnValue == NSAlertDefaultReturn) {
			NSString* name = [input stringValue];
			if ([name length] > 0)
			{
				BPFormula *formula = [BPFormula formulaWithName:name];
				[self prepareFormulae:@[formula] forOperation:kBPWindowOperationTap withOptions:nil];
			}
			else {
				[_appDelegate setRunningBackgroundTask:NO];
			}
		}
		else {
			[_appDelegate setRunningBackgroundTask:NO];
		}
	}
}

- (IBAction)installFormulaWithOptions:(id)sender
{
	if (_appDelegate.isRunningBackgroundTask)
	{
		[_appDelegate displayBackgroundWarning];
		return;
	}

	NSInteger selectedIndex = [self.tableView_formulae selectedRow];
	BPFormula *formula = [self.formulaeDataSource formulaAtIndex:selectedIndex];
	if (formula) {
		self.formulaOptionsWindowController = [BPFormulaOptionsWindowController runFormula:formula withCompletionBlock:^(NSArray *options) {
			[self prepareFormulae:@[formula] forOperation:kBPWindowOperationInstall withOptions:options];
		}];
	}
}

- (IBAction)upgradeSelectedFormulae:(id)sender {
	NSMutableString *names = [NSMutableString string];
	NSIndexSet *indexes = [self.tableView_formulae selectedRowIndexes];
	NSArray *selectedFormulae = [self.formulaeDataSource formulasAtIndexSet:indexes];
	[selectedFormulae enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([names compare:@""] == NSOrderedSame) {
			[names appendString:[obj name]];
		} else {
			[names appendFormat:@", %@", [obj name]];
		}
	}];

	NSAlert *alert = [NSAlert alertWithMessageText:@"Attention!" defaultButton:@"Yes" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"Are you sure you want to upgrade these formulae: '%@'?", names];
	[alert.window setTitle:@"Cakebrew"];
	if ([alert runModal] == NSAlertDefaultReturn) {
		[self prepareFormulae:selectedFormulae forOperation:kBPWindowOperationUpgrade withOptions:nil];
	}
}


- (IBAction)upgradeAllOutdatedFormulae:(id)sender {
	NSAlert *alert = [NSAlert alertWithMessageText:@"Attention!" defaultButton:@"Yes" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"Are you sure you want to upgrade all outdated formulae?"];
	[alert.window setTitle:@"Cakebrew"];
	if ([alert runModal] == NSAlertDefaultReturn) {
		[self prepareFormulae:nil forOperation:kBPWindowOperationUpgrade withOptions:nil];
	}
}

- (IBAction)updateHomebrew:(id)sender
{
	[self.outlineView_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:8] byExtendingSelection:NO];
	[self.updateViewController runStopUpdate:nil];
}

- (IBAction)openSelectedFormulaWebsite:(id)sender {
	NSInteger selectedIndex = [self.tableView_formulae selectedRow];
	BPFormula *formula = [self.formulaeDataSource formulaAtIndex:selectedIndex];
	if (formula) {
		[[NSWorkspace sharedWorkspace] openURL:formula.website];
	}
}

- (IBAction)searchFormulasFieldDidChange:(id)sender {
	NSSearchField *searchField = sender;
	NSString *searchPhrase = searchField.stringValue;
	if ([searchPhrase isEqualToString:@""]) {
		_isSearching = NO;
		[self configureTableForListing:kBPListAll];
	} else {
		[[BPHomebrewManager sharedManager] updateSearchWithName:searchPhrase];
	}
}

- (IBAction)beginFormulaSearch:(id)sender {
    if (![self.toolbar isVisible]) {
        [self.toolbar setVisible:YES];
    }
	[self.searchField becomeFirstResponder];
}

@end
