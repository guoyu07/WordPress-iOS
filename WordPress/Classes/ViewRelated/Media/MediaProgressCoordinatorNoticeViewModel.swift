enum MediaNoticeUserInfoKey {
    static let blogID = "blog_id"
    static let failedMediaIDs = "failed_media_ids"
    static let mediaIDs = "media_ids"
}

struct MediaProgressCoordinatorNoticeViewModel {
    private let mediaProgressCoordinator: MediaProgressCoordinator
    private let progress: Progress
    private let successfulMedia: [Media]
    private let failedMedia: [Media]

    init?(mediaProgressCoordinator: MediaProgressCoordinator) {
        guard !mediaProgressCoordinator.isRunning,
            let progress = mediaProgressCoordinator.mediaGlobalProgress else {
                return nil
        }

        self.mediaProgressCoordinator = mediaProgressCoordinator
        self.progress = progress

        successfulMedia = mediaProgressCoordinator.successfulMedia
        failedMedia = mediaProgressCoordinator.failedMedia
    }

    private var uploadSuccessful: Bool {
        return !mediaProgressCoordinator.hasFailedMedia
    }

    var notice: Notice? {
        if uploadSuccessful {
            return successNotice
        } else {
            return failureNotice
        }
    }

    private var successNotice: Notice {
        guard let blog = blogInContext else {
            return Notice(title: title, notificationInfo: notificationInfo)
        }

        return Notice(title: title,
                      feedbackType: .success,
                      notificationInfo: notificationInfo,
                      actionTitle: actionTitle,
                      actionHandler: {
                        MediaNoticeNavigationCoordinator.presentEditor(for: blog, source: "media_upload_notice", media: self.successfulMedia)
        })
    }

    private var failureNotice: Notice {
        return Notice(title: title,
                      message: message,
                      feedbackType: .error,
                      notificationInfo: notificationInfo,
                      actionTitle: NSLocalizedString("Retry", comment: "User action to retry media upload."),
                      actionHandler: {
                        for media in self.failedMedia {
                            MediaCoordinator.shared.retryMedia(media)
                        }
        })
    }

    private var notificationInfo: NoticeNotificationInfo {
        var userInfo = [String: Any]()

        if let blog = blogInContext {
            userInfo[MediaNoticeUserInfoKey.blogID] = blog.objectID.uriRepresentation().absoluteString
        }

        if uploadSuccessful {
            userInfo[MediaNoticeUserInfoKey.mediaIDs] = successfulMedia.map({ $0.objectID.uriRepresentation().absoluteString })
        } else {
            userInfo[MediaNoticeUserInfoKey.failedMediaIDs] = failedMedia.map({ $0.objectID.uriRepresentation().absoluteString })
        }

        return NoticeNotificationInfo(identifier: UUID().uuidString,
                                      categoryIdentifier: notificationCategoryIdentifier,
                                      userInfo: userInfo)
    }

    private var notificationCategoryIdentifier: String {
        return uploadSuccessful ? "media-upload-success" : "media-upload-failure"
    }

    var title: String {
        if uploadSuccessful {
            let completedUnits = progress.completedUnitCount
            if completedUnits == 1 {
                return NSLocalizedString("Media uploaded (1 file)", comment: "Alert displayed to the user when a single media item has uploaded successfully.")
            } else {
                return String(format: NSLocalizedString("Media uploaded (%ld files)", comment: "Alert displayed to the user when multiple media items have uploaded successfully."), completedUnits)
            }
        } else {
            let failedUnits = mediaProgressCoordinator.failedMediaIDs.count
            if failedUnits == 1 {
                return NSLocalizedString("1 file not uploaded", comment: "Alert displayed to the user when a single media item has failed to upload.")
            } else {
                return String(format: NSLocalizedString("%ld files not uploaded", comment: "Alert displayed to the user when multiple media items have failed to upload."), failedUnits)
            }
        }
    }

    var message: String? {
        guard !uploadSuccessful else {
            return nil
        }

        switch progress.completedUnitCount {
        case 1:
            return NSLocalizedString("1 file successfully uploaded", comment: "Alert displayed to the user when a single media item has failed to upload.")
        case 1...:
            return String(format: NSLocalizedString("%ld files successfully uploaded", comment: "Alert displayed to the user when multiple media items have failed to upload."), progress.completedUnitCount)
        default: return nil
        }
    }

    var actionTitle: String {
        if uploadSuccessful {
            return NSLocalizedString("Write Post", comment: "Button title. Opens the editor to write a new post.")
        } else {
            return NSLocalizedString("Retry", comment: "Button title, displayed when media has failed to upload. Allows the user to try the upload again.")
        }
    }

    private var blogInContext: Blog? {
        guard let mediaID = mediaProgressCoordinator.inProgressMediaIDs.first,
            let media = mediaProgressCoordinator.media(withIdentifier: mediaID) else {
                return nil
        }

        let context = ContextManager.sharedInstance().mainContext

        var blog = media.blog
        if blog.managedObjectContext != context,
            let objectInContext = try? context.existingObject(with: blog.objectID),
            let blogInContext = objectInContext as? Blog {
            blog = blogInContext
        }

        return blog
    }
}
