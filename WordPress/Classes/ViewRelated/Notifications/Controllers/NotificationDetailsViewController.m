#import "NotificationDetailsViewController.h"

#import "WordPressAppDelegate.h"
#import <Simperium/Simperium.h>

#import "Blog.h"
#import "Notification.h"

#import "ContextManager.h"

#import "BlogService.h"
#import "CommentService.h"
#import "ReaderSiteService.h"

#import "WPWebViewController.h"
#import "ReaderPostDetailViewController.h"
#import "StatsViewController.h"
#import "EditCommentViewController.h"

#import "WordPress-Swift.h"

#import "NSURL+Util.h"
#import "NSScanner+Helpers.h"
#import "UIActionSheet+Helpers.h"
#import "UIAlertView+Blocks.h"
#import "NSObject+Helpers.h"
#import "NSDate+StringFormatting.h"



#pragma mark ==========================================================================================
#pragma mark Constants
#pragma mark ==========================================================================================

static UIEdgeInsets NotificationTableInsetsPhone    = {0.0f,  0.0f, 20.0f, 0.0f};
static UIEdgeInsets NotificationTableInsetsPad      = {40.0f, 0.0f, 20.0f, 0.0f};

typedef NS_ENUM(NSInteger, NotificationSection) {
    NotificationSectionHeader,
    NotificationSectionBody,
    NotificationSectionCount
};

static NSInteger NotificationSectionHeaderRows  = 1;
static CGFloat NotificationSectionSeparator     = 10;


#pragma mark ==========================================================================================
#pragma mark Private
#pragma mark ==========================================================================================

@interface NotificationDetailsViewController () <SPBucketDelegate, EditCommentViewControllerDelegate>

// Outlets
@property (nonatomic,   weak) IBOutlet UITableView          *tableView;
@property (nonatomic,   weak) IBOutlet UIGestureRecognizer  *tableGesturesRecognizer;
@property (nonatomic, strong) ReplyTextView                 *replyTextView;

// Table Helpers
@property (nonatomic, strong) NSDictionary                  *layoutCellMap;
@property (nonatomic, strong) NSDictionary                  *reuseIdentifierMap;
@property (nonatomic, assign) NSInteger                     sectionCount;
@property (nonatomic, assign) NSInteger                     headerSectionIndex;
@property (nonatomic, assign) NSInteger                     bodySectionIndex;

// Keyboard Helpers
@property (nonatomic, assign) CGFloat                       keyboardBottomDelta;
@property (nonatomic, assign) BOOL                          isKeyboardVisible;
@end


#pragma mark ==========================================================================================
#pragma mark NotificationDetailsViewController
#pragma mark ==========================================================================================

@implementation NotificationDetailsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title                          = self.note.title;
    self.restorationClass               = [self class];
    self.view.backgroundColor           = [WPStyleGuide itsEverywhereGrey];
    
    self.tableView.contentInset         = IS_IPAD ? NotificationTableInsetsPad : NotificationTableInsetsPhone;
    self.tableView.backgroundColor      = [WPStyleGuide itsEverywhereGrey];

    self.reuseIdentifierMap = @{
        @(NoteBlockGroupTypesSnippet)   : NoteBlockSnippetTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypesText)      : NoteBlockTextTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypesComment)   : NoteBlockCommentTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypesImage)     : NoteBlockImageTableViewCell.reuseIdentifier,
        @(NoteBlockGroupTypesUser)      : NoteBlockUserTableViewCell.reuseIdentifier
    };
    
    Simperium *simperium                = [[WordPressAppDelegate sharedWordPressApplicationDelegate] simperium];
    SPBucket *notificationsBucket       = [simperium bucketForName:NSStringFromClass([Notification class])];
    notificationsBucket.delegate        = self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self reloadData];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(handleKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self.replyTextView resignFirstResponder];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData
{
    // Hide the header, if needed
    self.sectionCount       = NotificationSectionCount;
    self.headerSectionIndex = NotificationSectionHeader;
    self.bodySectionIndex   = NotificationSectionBody;
    
    if (self.note.headerBlockGroup == nil) {
        --_sectionCount;
        --_headerSectionIndex;
        --_bodySectionIndex;
    }
    
    [self.tableView reloadData];
    [self attachReplyViewIfNeeded];
}


#pragma mark - Autolayout Helpers

- (NSDictionary *)layoutCellMap
{
    if (_layoutCellMap) {
        return _layoutCellMap;
    }
    
    NSString *storyboardID  = NSStringFromClass([self class]);
    NotificationDetailsViewController *detailsViewController = [self.storyboard instantiateViewControllerWithIdentifier:storyboardID];
    
    [detailsViewController loadView];
    
    UITableView *tableView  = detailsViewController.tableView;

    _layoutCellMap = @{
        @(NoteBlockGroupTypesSnippet)   : [tableView dequeueReusableCellWithIdentifier:NoteBlockSnippetTableViewCell.reuseIdentifier],
        @(NoteBlockGroupTypesText)      : [tableView dequeueReusableCellWithIdentifier:NoteBlockTextTableViewCell.reuseIdentifier],
        @(NoteBlockGroupTypesComment)   : [tableView dequeueReusableCellWithIdentifier:NoteBlockCommentTableViewCell.reuseIdentifier],
        @(NoteBlockGroupTypesImage)     : [tableView dequeueReusableCellWithIdentifier:NoteBlockImageTableViewCell.reuseIdentifier],
        @(NoteBlockGroupTypesUser)      : [tableView dequeueReusableCellWithIdentifier:NoteBlockUserTableViewCell.reuseIdentifier]
    };
    
    return _layoutCellMap;
}


#pragma mark - Reply View Helpers

- (void)attachReplyViewIfNeeded
{
    if (self.replyTextView) {
        return;
    }
    
    // Attach the Reply component only if the noficiation has a comment, and it can be replied-to
    NotificationBlockGroup *group   = [self.note blockGroupOfType:NoteBlockGroupTypesComment];
    NotificationBlock *block        = [group blockOfType:NoteBlockTypesComment];
    if (![block actionForKey:NoteActionReplyKey]) {
        return;
    }
    
    ReplyTextView *replyTextView    = [[ReplyTextView alloc] initWithWidth:CGRectGetWidth(self.view.frame)];
    replyTextView.placeholder       = NSLocalizedString(@"Write a reply…", @"Placeholder text for inline compose view");
    replyTextView.replyText         = [NSLocalizedString(@"Reply", @"") uppercaseString];
    replyTextView.onReply           = ^(NSString *content) {
    };
    self.replyTextView              = replyTextView;
    
    // Attach!
    [self.view addSubview:replyTextView];
    
    // Adjust position + use an internal ReplaceTextView instance as inputAccessoryView
    [replyTextView alignAtBottomOfSuperview];
    [replyTextView setupProxyAccessoryView];
    
    // Setup the Table Insets
    UIEdgeInsets tableViewInsets    = self.tableView.contentInset;
    tableViewInsets.bottom          += CGRectGetHeight(replyTextView.frame);
    self.tableView.contentInset     = tableViewInsets;
    
    
#warning UNHACK
//  Status: Approved
//  Approve Parent
    
    //    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    //    CommentService *service = [[CommentService alloc] initWithManagedObjectContext:context];
    //
    //    [service replyCommentWithID:block.metaCommentID siteID:block.metaSiteID content:@"Reply?" success:nil failure:nil];
}


#pragma mark - SPBucketDeltage Methods

- (void)bucket:(SPBucket *)bucket didChangeObjectForKey:(NSString *)key forChangeType:(SPBucketChangeType)changeType memberNames:(NSArray *)memberNames
{
    // Reload the table, if *our* notification got updated
    if ([self.note.simperiumKey isEqualToString:key]) {
        [self reloadData];
    }
}


#pragma mark - UIViewController Restoration

+ (UIViewController *)viewControllerWithRestorationIdentifierPath:(NSArray *)identifierComponents coder:(NSCoder *)coder
{
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    NSString *noteID = [coder decodeObjectForKey:NSStringFromClass([Notification class])];
    if (!noteID) {
        return nil;
    }
    
    NSManagedObjectID *objectID = [context.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:noteID]];
    if (!objectID) {
        return nil;
    }
    
    NSError *error = nil;
    Notification *restoredNotification = (Notification *)[context existingObjectWithID:objectID error:&error];
    if (error || !restoredNotification) {
        return nil;
    }
    
    UIStoryboard *storyboard = [coder decodeObjectForKey:UIStateRestorationViewControllerStoryboardKey];
    if (!storyboard) {
        return nil;
    }
    
    NotificationDetailsViewController *vc   = [storyboard instantiateViewControllerWithIdentifier:NSStringFromClass([self class])];
    vc.restorationIdentifier                = [identifierComponents lastObject];
    vc.restorationClass                     = [NotificationDetailsViewController class];
    vc.note                                 = restoredNotification;
    
    return vc;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    NSString *noteIdKey = NSStringFromClass([Notification class]);
    [coder encodeObject:[self.note.objectID.URIRepresentation absoluteString] forKey:noteIdKey];
    [super encodeRestorableStateWithCoder:coder];
}


#pragma mark - Helpers

- (NotificationBlockGroup *)blockGroupForIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.section == _headerSectionIndex) ? _note.headerBlockGroup : _note.bodyBlockGroups[indexPath.row];
}


#pragma mark - UITableViewDelegate Methods

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    /**
        Note
        This is a workaround. iOS 7 + grouped cells result in an extra top spacing.
        Ref.: http://stackoverflow.com/questions/17699831/how-to-change-height-of-grouped-uitableview-header
     */

    return (section == _bodySectionIndex && _sectionCount > 1) ? NotificationSectionSeparator : CGFLOAT_MIN;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (section == _headerSectionIndex) ? NotificationSectionHeaderRows : self.note.bodyBlockGroups.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NotificationBlockGroup *blockGroup      = [self blockGroupForIndexPath:indexPath];
    NoteBlockTableViewCell *tableViewCell   = self.layoutCellMap[@(blockGroup.type)] ?: self.layoutCellMap[@(NoteBlockGroupTypesText)];
    
    [self setupCell:tableViewCell blockGroup:blockGroup];

    CGFloat height = [tableViewCell layoutHeightWithWidth:CGRectGetWidth(self.tableView.bounds)];
    
    return height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NotificationBlockGroup *blockGroup      = [self blockGroupForIndexPath:indexPath];
    NSString *reuseIdentifier               = self.reuseIdentifierMap[@(blockGroup.type)] ?: self.reuseIdentifierMap[@(NoteBlockGroupTypesText)];
    NoteBlockTableViewCell *cell            = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    [self setupCell:cell blockGroup:blockGroup];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NotificationBlockGroup *group = [self blockGroupForIndexPath:indexPath];

    // User Blocks: Push the associated blog, if any
    if (group.type == NoteBlockGroupTypesUser) {
        
        NotificationBlock *block    = [group blockOfType:NoteBlockTypesUser];
        [self openURL:[NSURL URLWithString:block.metaLinksHome]];
        
    } else if (group.type == NoteBlockGroupTypesSnippet) {
        
        NotificationBlock *block    = [group blockOfType:NoteBlockTypesText];
        NotificationRange *range    = block.ranges.firstObject;

        [self openURL:range.url];
    }
}


#pragma mark - NoteBlockTableViewCell Helpers

- (void)setupCell:(NoteBlockTableViewCell *)cell blockGroup:(NotificationBlockGroup *)blockGroup
{
    // Note: This is gonna look awesome in Swift
    if (blockGroup.type == NoteBlockGroupTypesSnippet) {
        [self setupSnippetCell:(NoteBlockSnippetTableViewCell *)cell blockGroup:blockGroup];
        
    } else if (blockGroup.type == NoteBlockGroupTypesUser) {
        [self setupUserCell:(NoteBlockUserTableViewCell *)cell blockGroup:blockGroup];
        
    } else if (blockGroup.type == NoteBlockGroupTypesComment){
        [self setupCommentCell:(NoteBlockCommentTableViewCell *)cell blockGroup:blockGroup];
        
    } else if (blockGroup.type == NoteBlockGroupTypesImage) {
        [self setupImageCell:(NoteBlockImageTableViewCell *)cell blockGroup:blockGroup];
        
    } else {
        [self setupTextCell:(NoteBlockTextTableViewCell *)cell blockGroup:blockGroup];
    }
}

- (void)setupSnippetCell:(NoteBlockSnippetTableViewCell *)cell blockGroup:(NotificationBlockGroup *)blockGroup
{
    NotificationBlock *gravatarBlock    = [blockGroup blockOfType:NoteBlockTypesImage];
    NotificationBlock *snippetBlock     = [blockGroup blockOfType:NoteBlockTypesText];
    NotificationMedia *media            = gravatarBlock.media.firstObject;
    
    cell.name                           = gravatarBlock.text;
    cell.snippet                        = snippetBlock.text;
    
    [cell downloadGravatarWithURL:media.mediaURL];
}

- (void)setupUserCell:(NoteBlockUserTableViewCell *)cell blockGroup:(NotificationBlockGroup *)blockGroup
{
    NotificationBlock *userBlock    = blockGroup.blocks.firstObject;
    NotificationMedia *media        = [userBlock.media firstObject];
    
    NSAssert(userBlock, nil);
    
    __weak __typeof(self) weakSelf  = self;
    
    cell.name                       = userBlock.text;
    cell.blogTitle                  = userBlock.metaTitlesHome;
    cell.isFollowEnabled            = [userBlock isActionEnabled:NoteActionFollowKey];
    cell.isFollowOn                 = [userBlock isActionOn:NoteActionFollowKey];
    cell.onFollowClick              = ^() {
        [weakSelf followSiteWithBlock:userBlock];
    };
    cell.onUnfollowClick            = ^() {
        [weakSelf unfollowSiteWithBlock:userBlock];
    };
    
    [cell downloadGravatarWithURL:media.mediaURL];
}

- (void)setupCommentCell:(NoteBlockCommentTableViewCell *)cell blockGroup:(NotificationBlockGroup *)blockGroup
{
    NotificationBlock *commentBlock = [blockGroup blockOfType:NoteBlockTypesComment];
    NotificationBlock *userBlock    = [blockGroup blockOfType:NoteBlockTypesUser];
    NotificationMedia *media        = userBlock.media.firstObject;
    
    NSAssert(commentBlock, nil);
    NSAssert(userBlock, nil);
    
    __weak __typeof(self) weakSelf  = self;
    
    cell.isLikeEnabled              = [commentBlock isActionEnabled:NoteActionLikeKey];
    cell.isApproveEnabled           = [commentBlock isActionEnabled:NoteActionApproveKey];
    cell.isTrashEnabled             = [commentBlock isActionEnabled:NoteActionTrashKey];
    cell.isMoreEnabled              = [commentBlock isActionEnabled:NoteActionApproveKey];

    cell.isLikeOn                   = [commentBlock isActionOn:NoteActionLikeKey];
    cell.isApproveOn                = [commentBlock isActionOn:NoteActionApproveKey];
    
    cell.name                       = userBlock.text;
    cell.timestamp                  = [self.note.timestampAsDate shortString];
    cell.attributedText             = commentBlock.regularFormattedText;

    cell.onUrlClick                 = ^(NSURL *url){
        [weakSelf openURL:url];
    };
    
    cell.onLikeClick                = ^(){
        [weakSelf likeCommentWithBlock:commentBlock];
    };
    
    cell.onUnlikeClick              = ^(){
        [weakSelf unlikeCommentWithBlock:commentBlock];
    };
    
    cell.onApproveClick             = ^(){
        [weakSelf approveCommentWithBlock:commentBlock];
    };

    cell.onUnapproveClick             = ^(){
        [weakSelf unapproveCommentWithBlock:commentBlock];
    };
    
    cell.onTrashClick               = ^(){
        [weakSelf trashCommentWithBlock:commentBlock];
    };
    
    cell.onMoreClick                = ^(){
        [weakSelf displayMoreActionsWithBlock:commentBlock];
    };
    
    [cell downloadGravatarWithURL:media.mediaURL];
}

- (void)setupImageCell:(NoteBlockImageTableViewCell *)cell blockGroup:(NotificationBlockGroup *)blockGroup
{
    NotificationBlock *imageBlock   = blockGroup.blocks.firstObject;
    NSAssert(imageBlock, nil);
    
    NotificationMedia *media        = imageBlock.media.firstObject;
    
    [cell downloadImageWithURL:media.mediaURL];
}

- (void)setupTextCell:(NoteBlockTextTableViewCell *)cell blockGroup:(NotificationBlockGroup *)blockGroup
{
    NotificationBlock *textBlock    = blockGroup.blocks.firstObject;
    NSAssert(textBlock, nil);
    
    __weak __typeof(self) weakSelf  = self;
    
    cell.attributedText             = textBlock.regularFormattedText;
    cell.onUrlClick                 = ^(NSURL *url){
        [weakSelf openURL:url];
    };
}


#pragma mark - Helpers

- (void)openURL:(NSURL *)url
{
    NotificationRange *range = [self.note notificationRangeWithUrl:url];
    
    if ([self displayReaderWithNotificationRange:range]) {
        return;
    }
    
    if ([self displayStatsWithNotificationRange:range]) {
        return;
    }
    
    if ([self displayWebViewWithURL:url]) {
        return;
    }
    
    [self.tableView deselectSelectedRowWithAnimation:YES];
}

- (BOOL)displayReaderWithNotificationRange:(NotificationRange *)range
{
    BOOL success = ((range.isPost || range.isComment) && range.postID && range.siteID);
    if (success) {
        [self performSegueWithIdentifier:NSStringFromClass([ReaderPostDetailViewController class]) sender:range];
    }
    return success;
}

- (BOOL)displayStatsWithNotificationRange:(NotificationRange *)range
{
    if (!range.isStats || !range.siteID) {
        return false;
    }
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    BlogService *service            = [[BlogService alloc] initWithManagedObjectContext:context];
    Blog *blog                      = [service blogByBlogId:range.siteID];
    
    BOOL success = blog.isWPcom;
    if (success) {
        [self performSegueWithIdentifier:NSStringFromClass([StatsViewController class]) sender:blog];
    }
    return success;
}

- (BOOL)displayWebViewWithURL:(NSURL *)url
{
    BOOL success = url != nil;
    if (success) {
        [self performSegueWithIdentifier:NSStringFromClass([WPWebViewController class]) sender:url];
    }
    return success;
}

- (void)displayMoreActionsWithBlock:(NotificationBlock *)block
{
    NSString *editTitle     = NSLocalizedString(@"Edit Comment", @"Edit a comment");
    NSString *spamTitle     = NSLocalizedString(@"Mark as Spam", @"Mark a comment as spam");
    NSString *cancelTitle   = NSLocalizedString(@"Cancel", nil);
    
    // Prepare the More Menu
    NSMutableArray *otherButtonTitles  = [NSMutableArray array];
    
    if ([block isActionEnabled:NoteActionEditKey]) {
        [otherButtonTitles addObject:editTitle];
    }
    
    if ([block isActionEnabled:NoteActionSpamKey]) {
        [otherButtonTitles addObject:spamTitle];
    }
    
    // Render the actionSheet
    __typeof(self) __weak weakSelf = self;
    UIActionSheet *actionSheet  = [[UIActionSheet alloc] initWithTitle:nil
                                                     cancelButtonTitle:cancelTitle
                                                destructiveButtonTitle:nil
                                                     otherButtonTitles:otherButtonTitles
                                                            completion:^(NSString *buttonTitle) {
                                                                if ([buttonTitle isEqualToString:editTitle]) {
                                                                    [weakSelf editCommentWithBlock:block];
                                                                } else if ([buttonTitle isEqualToString:spamTitle]) {
                                                                    [weakSelf spamCommentWithBlock:block];
                                                                }
                                                            }];
    
    [actionSheet showInView:self.view.window];
}


#pragma mark - Action Handlers

- (void)followSiteWithBlock:(NotificationBlock *)block
{
    [WPAnalytics track:WPAnalyticsStatNotificationFollowAction];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    ReaderSiteService *service      = [[ReaderSiteService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service followSiteWithID:block.metaSiteID.integerValue success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionFollowKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(true) forKey:NoteActionFollowKey];
}

- (void)unfollowSiteWithBlock:(NotificationBlock *)block
{
    [WPAnalytics track:WPAnalyticsStatNotificationUnfollowAction];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    ReaderSiteService *service      = [[ReaderSiteService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service unfollowSiteWithID:block.metaSiteID.integerValue success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionFollowKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(false) forKey:NoteActionFollowKey];
}

- (void)likeCommentWithBlock:(NotificationBlock *)block
{
    [WPAnalytics track:WPAnalyticsStatNotificationLiked];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service likeCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionLikeKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(true) forKey:NoteActionLikeKey];
}

- (void)unlikeCommentWithBlock:(NotificationBlock *)block
{
    [WPAnalytics track:WPAnalyticsStatNotificationUnliked];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service unlikeCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionLikeKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(false) forKey:NoteActionLikeKey];
}

- (void)approveCommentWithBlock:(NotificationBlock *)block
{
    [WPAnalytics track:WPAnalyticsStatNotificationApproved];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service approveCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionApproveKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(true) forKey:NoteActionApproveKey];
}

- (void)unapproveCommentWithBlock:(NotificationBlock *)block
{
    [WPAnalytics track:WPAnalyticsStatNotificationUnapproved];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service unapproveCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:^(NSError *error) {
        [block removeActionOverrideForKey:NoteActionApproveKey];
        [weakSelf reloadData];
    }];
    
    [block setActionOverrideValue:@(false) forKey:NoteActionApproveKey];
}

- (void)spamCommentWithBlock:(NotificationBlock *)block
{
    UIAlertViewCompletionBlock completion = ^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == alertView.cancelButtonIndex) {
            return;
        }
        
        [WPAnalytics track:WPAnalyticsStatNotificationFlaggedAsSpam];
        
        NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
        CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
        
        [service spamCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:nil];
        
        [self.navigationController popToRootViewControllerAnimated:YES];
    };
    
    NSString *message = NSLocalizedString(@"Are you sure you want to mark this comment as Spam?",
                                          @"Message asking for confirmation before marking a comment as spam");
    
    [UIAlertView showWithTitle:NSLocalizedString(@"Confirm", @"Confirm")
                       message:message
             cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
             otherButtonTitles:@[NSLocalizedString(@"Spam", @"Spam")]
                      tapBlock:completion];
}

- (void)trashCommentWithBlock:(NotificationBlock *)block
{
    // Callback Block
    UIAlertViewCompletionBlock completion = ^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == alertView.cancelButtonIndex) {
            return;
        }
        
        [WPAnalytics track:WPAnalyticsStatNotificationTrashed];
        
        NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
        CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
        
        [service deleteCommentWithID:block.metaCommentID siteID:block.metaSiteID success:nil failure:nil];
        
        [self.navigationController popToRootViewControllerAnimated:YES];
    };
 
    // Show the alertView
    NSString *message = NSLocalizedString(@"Are you sure you want to delete this comment?",
                                          @"Message asking for confirmation on comment deletion");
    
    [UIAlertView showWithTitle:NSLocalizedString(@"Confirm", @"Confirm")
                       message:message
             cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
             otherButtonTitles:@[NSLocalizedString(@"Delete", @"Delete")]
                      tapBlock:completion];
}

- (void)editCommentWithBlock:(NotificationBlock *)block
{
    [self performSegueWithIdentifier:NSStringFromClass([EditCommentViewController class]) sender:block];
}


#pragma mark - EditCommentViewControllerDelegate

- (void)editCommentViewController:(EditCommentViewController *)sender didUpdateContent:(NSString *)newContent
{
    NSAssert([sender.userInfo isKindOfClass:[NotificationBlock class]], nil);
    
    // Local Override: Temporary hack until Simperium reflects the REST op
    NotificationBlock *block        = sender.userInfo;
    block.textOverride              = newContent;
    [self reloadData];
    
    // Hit the backend
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    CommentService *service         = [[CommentService alloc] initWithManagedObjectContext:context];
    __typeof(self) __weak weakSelf  = self;
    
    [service updateCommentWithID:block.metaCommentID siteID:block.metaSiteID content:newContent success:nil failure:^(NSError *error) {
        [UIAlertView showWithTitle:nil
                           message:NSLocalizedString(@"Couldn't Update Comment. Please, try again later",
                                                     @"Error displayed if a comment fails to get updated")
                 cancelButtonTitle:NSLocalizedString(@"Accept", nil)
                 otherButtonTitles:nil
                          tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                      block.textOverride = nil;
                      [weakSelf reloadData];
                 }];
    }];
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)editCommentViewControllerFinished:(EditCommentViewController *)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - Storyboard Helpers

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:NSStringFromClass([WPWebViewController class])]) {
        WPWebViewController *webViewController          = segue.destinationViewController;
        webViewController.url                           = (NSURL *)sender;
        
    } else if([segue.identifier isEqualToString:NSStringFromClass([StatsViewController class])]) {
        StatsViewController *statsViewController        = segue.destinationViewController;
        statsViewController.blog                        = (Blog *)sender;
        
    } else if([segue.identifier isEqualToString:NSStringFromClass([ReaderPostDetailViewController class])]) {
        ReaderPostDetailViewController *readerViewController = segue.destinationViewController;
        NotificationRange *range                        = (NotificationRange *)sender;
        [readerViewController setupWithPostID:range.postID siteID:range.siteID];
        
    } else if ([segue.identifier isEqualToString:NSStringFromClass([EditCommentViewController class])]) {
        NotificationBlock *block                        = sender;
        
        UINavigationController *navigationController    = segue.destinationViewController;
        EditCommentViewController *editViewController   = (EditCommentViewController *)navigationController.topViewController;
        editViewController.delegate                     = self;
        editViewController.content                      = block.text;
        editViewController.userInfo                     = block;
    }
}


#pragma mark - Notification Helpers

- (void)handleKeyboardWillShow:(NSNotification *)notification
{
    if (self.isKeyboardVisible) {
        return;
    }
    
    NSDictionary* userInfo                  = notification.userInfo;
    
    // Convert the rect to view coordinates: enforce the current orientation!
    CGRect kbRect                           = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kbRect                                  = [self.view convertRect:kbRect fromView:nil];
    
    CGRect viewFrame                        = self.view.frame;
    CGFloat bottomInset                     = CGRectGetHeight(kbRect) - (CGRectGetMaxY(kbRect) - CGRectGetHeight(viewFrame) + CGRectGetHeight(self.replyTextView.bounds));
    
    UIEdgeInsets newContentInsets           = self.tableView.contentInset;
    newContentInsets.bottom                 += bottomInset;
    
    self.replyTextView.proxyAccessoryAlpha  = 0;
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:[userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue]];

    self.tableView.contentInset             = newContentInsets;
    self.replyTextView.proxyAccessoryAlpha  = 1;

    [UIView commitAnimations];
    
    self.keyboardBottomDelta                = bottomInset;
    self.isKeyboardVisible                  = true;
    self.tableGesturesRecognizer.enabled    = true;
}

- (void)handleKeyboardWillHide:(NSNotification *)notification
{
    if (!self.isKeyboardVisible) {
        return;
    }
    
    NSDictionary* userInfo                  = notification.userInfo;
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:[userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue]];
    
    UIEdgeInsets newContentInsets           = self.tableView.contentInset;
    newContentInsets.bottom                 -= self.keyboardBottomDelta;
    self.tableView.contentInset             = newContentInsets;
    
    [UIView commitAnimations];
    
    self.isKeyboardVisible                  = false;
    self.tableGesturesRecognizer.enabled    = false;
}


#pragma mark - Gestures Recognizer Delegate

- (IBAction)dismissKeyboardIfNeeded:(id)sender
{
    // Dismiss the reply field when tapping on the tableView
    [self.view.window endEditing:YES];
}

@end
