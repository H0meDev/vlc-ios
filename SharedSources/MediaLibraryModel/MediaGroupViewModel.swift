/*****************************************************************************
 * MediaGroupViewModel.swift
 *
 * Copyright © 2020 VLC authors and VideoLAN
 *
 * Authors: Soomin Lee <bubu@mikan.io>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

class MediaGroupViewModel: MLBaseModel {
    typealias MLType = VLCMLMediaGroup

    var sortModel = SortModel([.alpha, .duration, .insertionDate, .lastModificationDate, .nbVideo])

    var observable = Observable<MediaLibraryBaseModelObserver>()

    var files: [VLCMLMediaGroup]

    var cellType: BaseCollectionViewCell.Type { return MovieCollectionViewCell.self }

    var medialibrary: MediaLibraryService

    var indicatorName: String = NSLocalizedString("VIDEO_GROUPS", comment: "")

    required init(medialibrary: MediaLibraryService) {
        self.medialibrary = medialibrary
        files = medialibrary.medialib.mediaGroups() ?? []
        medialibrary.observable.addObserver(self)
    }

    func append(_ item: VLCMLMediaGroup) {
        files.append(item)
    }

    func append(_ media: [VLCMLMedia], to mediaGroup: VLCMLMediaGroup) {
        let originIds = originMediaGroupsIds(from: media)

        for medium in media {
            mediaGroup.add(medium)
        }
        files = swapModels(with: [mediaGroup])
        filterFilesFromDeletion(of: originIds)
    }

    func delete(_ items: [VLCMLMediaGroup]) {
        for item in items {
            guard let media = item.media(of: .video) else {
                continue
            }

            for medium in media {
                medium.deleteMainFile()
            }
            item.destroy()
        }
        medialibrary.reload()
        filterFilesFromDeletion(of: items)
    }

    func rename(_ mediaGroup: VLCMLMediaGroup, to name: String) {
        if mediaGroup.nbMedia() == 1 && !mediaGroup.userInteracted() {
            guard let media = mediaGroup.media(of: .video)?.first else {
                assertionFailure("MediaGroupViewController: rename: Failed to retrieve media.")
                return
            }
            media.updateTitle(name)
        } else {
            mediaGroup.rename(withName: name)
        }
    }

    func sort(by criteria: VLCMLSortingCriteria, desc: Bool) {
        files = medialibrary.medialib.mediaGroups(with: criteria, desc: desc) ?? []
        sortModel.currentSort = criteria
        sortModel.desc = desc
        observable.observers.forEach() {
            $0.value.observer?.mediaLibraryBaseModelReloadView()
        }
    }

    func create(with name: String,
                from mediaGroupIds: [VLCMLIdentifier]? = nil, content: [VLCMLMedia]) -> Bool {
        guard let mediaGroup = medialibrary.medialib.createMediaGroup(withName: name) else {
            assertionFailure("MediaGroupViewModel: Unable to create a mediagroup with name: \(name)")
            return false
        }
        append(mediaGroup)
        content.forEach() { mediaGroup.add($0) }
        if let mediaGroupIds = mediaGroupIds {
            filterFilesFromDeletion(of: mediaGroupIds)
        }
        return true
    }

    func create(with name: String, from mediaContent: [VLCMLMedia]) -> Bool {
        let originIds = originMediaGroupsIds(from: mediaContent)
        return create(with: name, from: originIds, content: mediaContent)
    }

    func unGroupMedia(_ media: [VLCMLMedia], from originMediaGroup: VLCMLMediaGroup) -> Bool {
        for medium in media {
            medium.removeFromGroup()
            guard let newGroup = medialibrary.medialib.createMediaGroup(withName: medium.title) else {
                return false
            }
            newGroup.add(medium)
        }
        if originMediaGroup.nbMedia() == 0 {
            filterFilesFromDeletion(of: [originMediaGroup])
            medialibrary.medialib.deleteMediaGroup(withIdentifier: originMediaGroup.identifier())
        }
        return true
    }
}

// MARK: - Private helpers

private extension MediaGroupViewModel {
    func originMediaGroupsIds(from media: [VLCMLMedia]) -> [VLCMLIdentifier] {
        var originIds = [VLCMLIdentifier]()
        media.forEach() {
            let groupId = $0.groupIdentifier()
            if !originIds.contains(groupId) {
                originIds.append(groupId)
            }
        }
        return originIds
    }
}

// MARK: - MediaLibraryObserver

extension MediaGroupViewModel: MediaLibraryObserver {
    func medialibrary(_ medialibrary: MediaLibraryService,
                      didAddMediaGroups mediaGroups: [VLCMLMediaGroup]) {
        for mediaGroup in mediaGroups {
            if !files.contains(where: { $0.identifier() == mediaGroup.identifier() }) {
                files.append(mediaGroup)
            }
        }
        observable.observers.forEach() {
            $0.value.observer?.mediaLibraryBaseModelReloadView()
        }
    }

    func medialibrary(_ medialibrary: MediaLibraryService,
                      didModifyMediaGroupsWithIds mediaGroupsIds: [NSNumber]) {
        var mediaGroups = [VLCMLMediaGroup]()

        mediaGroupsIds.forEach() {
            guard let safeMediaGroup = medialibrary.medialib.mediaGroup(withIdentifier: $0.int64Value)
                else {
                    return
            }
            mediaGroups.append(safeMediaGroup)
        }

        files = swapModels(with: mediaGroups)
        observable.observers.forEach() {
            $0.value.observer?.mediaLibraryBaseModelReloadView()
        }
    }

    func medialibrary(_ medialibrary: MediaLibraryService,
                      didDeleteMediaGroupsWithIds mediaGroupsIds: [NSNumber]) {
        files.removeAll {
            mediaGroupsIds.contains(NSNumber(value: $0.identifier()))
        }
        observable.observers.forEach() {
            $0.value.observer?.mediaLibraryBaseModelReloadView()
        }
    }

    // MARK: - Thumbnail

    func medialibrary(_ medialibrary: MediaLibraryService,
                      thumbnailReady media: VLCMLMedia,
                      type: VLCMLThumbnailSizeType, success: Bool) {
        guard success else {
            return
        }
        observable.observers.forEach() {
            $0.value.observer?.mediaLibraryBaseModelReloadView()
        }
    }
}

// MARK: - VLCMLMediaGroup - Search

extension VLCMLMediaGroup: SearchableMLModel {
    func contains(_ searchString: String) -> Bool {
        return name().lowercased().contains(searchString)
    }
}

// MARK: - VLCMLMediaGroup - MediaCollectionModel

extension VLCMLMediaGroup: MediaCollectionModel {
    func sortModel() -> SortModel? {
        return nil
    }

    func files(with criteria: VLCMLSortingCriteria,
               desc: Bool) -> [VLCMLMedia]? {
        // FIXME: For now force type of media to .video
        return media(of: .video, sort: criteria, desc: desc)
    }

    func title() -> String {
        return name()
    }
}

// MARK: - VLCMLMediaGroup - Helpers

extension VLCMLMediaGroup {
    func numberOfTracksString() -> String {
        let mediaCount = nbVideo()
        let tracksString = mediaCount > 1 ? NSLocalizedString("TRACKS", comment: "") : NSLocalizedString("TRACK", comment: "")
        return String(format: tracksString, mediaCount)
    }

    func accessibilityText() -> String? {
        return name() + " " + numberOfTracksString()
    }
}