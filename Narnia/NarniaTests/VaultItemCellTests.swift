//
//  VaultItemCellTests.swift
//  NarniaTests
//
//  Unit tests for VaultItemCell.displayCaption: the pure caption-selection
//  logic that backs the "Hide names" privacy setting (design spec §5). Folders
//  and documents show their name normally and a generic type word when
//  hide-names is on; photos, videos, and other kinds never show a caption.
//

import Testing
@testable import Narnia

struct VaultItemCellTests {

    // MARK: - Folders

    @Test func folderShowsNameWhenHideNamesOff() {
        #expect(
            VaultItemCell.displayCaption(name: "Taxes", kind: .folder, hideNames: false) == "Taxes"
        )
    }

    @Test func folderShowsGenericWordWhenHideNamesOn() {
        #expect(
            VaultItemCell.displayCaption(name: "Taxes", kind: .folder, hideNames: true) == "Folder"
        )
    }

    // MARK: - Documents

    @Test func documentShowsNameWhenHideNamesOff() {
        #expect(
            VaultItemCell.displayCaption(name: "Passport.pdf", kind: .document, hideNames: false) == "Passport.pdf"
        )
    }

    @Test func documentShowsGenericWordWhenHideNamesOn() {
        #expect(
            VaultItemCell.displayCaption(name: "Passport.pdf", kind: .document, hideNames: true) == "Document"
        )
    }

    // MARK: - Caption-less kinds (nil regardless of hideNames)

    @Test func photoNeverShowsCaption() {
        #expect(VaultItemCell.displayCaption(name: "IMG_0001", kind: .photo, hideNames: false) == nil)
        #expect(VaultItemCell.displayCaption(name: "IMG_0001", kind: .photo, hideNames: true) == nil)
    }

    @Test func videoNeverShowsCaption() {
        #expect(VaultItemCell.displayCaption(name: "Clip.mov", kind: .video, hideNames: false) == nil)
        #expect(VaultItemCell.displayCaption(name: "Clip.mov", kind: .video, hideNames: true) == nil)
    }

    @Test func otherNeverShowsCaption() {
        #expect(VaultItemCell.displayCaption(name: "blob.bin", kind: .other, hideNames: false) == nil)
        #expect(VaultItemCell.displayCaption(name: "blob.bin", kind: .other, hideNames: true) == nil)
    }
}
