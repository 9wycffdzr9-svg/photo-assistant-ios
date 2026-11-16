//
//  PhotoScanner.swift
//  相册扫描：只读元数据，不读图片数据。
//
//  2026-11-16 小鱼（v2）
//  上一版把「扫相册」和「读图片二进制」写在同一个循环里，结果手机上照片一多、
//  又有一堆在 iCloud 上，iOS 要一张张从云端拉，几百张排队就卡死了，界面一个数都不动。
//  现在拆开：这一层只取列表（毫秒级），真正的数据在 Uploader 里逐张拉。
//

import Foundation
import Photos

struct ScannedAsset {
    var localId: String
    var creationDate: Date?
    var mediaType: String        // "image" / "video"
    var filename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var estimatedBytes: Int      // 从 PHAssetResource 估的，读不到就是 0
}

final class PhotoScanner {

    /// 请求权限。回调 (是否给了, 是否是「仅选中的照片」)
    static func requestPermission(completion: @escaping (Bool, Bool) -> Void) {
        let handler: (PHAuthorizationStatus) -> Void = { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized: completion(true, false)
                case .limited:    completion(true, true)
                default:          completion(false, false)
                }
            }
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization(handler)
        }
    }

    static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 当前总数（不弹框、不读数据）
    static func count() -> Int {
        PHAsset.fetchAssets(with: nil).count
    }

    /// 只扫元数据。这一步应该几百毫秒就回来，因为不碰图片二进制。
    static func scan(since: Date?, limit: Int = 0,
                     progress: @escaping (Int, Int) -> Void,
                     completion: @escaping ([ScannedAsset]) -> Void) {

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let since = since {
            options.predicate = NSPredicate(format: "creationDate > %@", since as NSDate)
        }
        if limit > 0 { options.fetchLimit = limit }

        let result = PHAsset.fetchAssets(with: options)
        let total = result.count
        var out: [ScannedAsset] = []
        out.reserveCapacity(total)

        result.enumerateObjects { asset, index, _ in
            var bytes = 0
            // PHAssetResource 能给出原始文件大小，不用下载
            if let res = PHAssetResource.assetResources(for: asset).first {
                if let n = res.value(forKey: "fileSize") as? Int { bytes = n }
            }
            out.append(ScannedAsset(
                localId: asset.localIdentifier,
                creationDate: asset.creationDate,
                mediaType: asset.mediaType == .video ? "video" : "image",
                filename: (asset.value(forKey: "filename") as? String) ?? "asset_\(index)",
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                estimatedBytes: bytes
            ))
            // 每 50 张回报一次，别把主线程刷爆
            if index % 50 == 0 || index == total - 1 {
                let done = index + 1
                DispatchQueue.main.async { progress(done, total) }
            }
        }

        DispatchQueue.main.async { completion(out) }
    }

    /// 按 localId 取回单个 asset（上传时用）
    static func asset(withLocalId id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// 只对当前这一张读数据。这一步慢没关系，外面会显示「正在传第几张」。
    static func loadData(for asset: PHAsset, completion: @escaping (Data?) -> Void) {
        let opt = PHImageRequestOptions()
        opt.isNetworkAccessAllowed = true     // iCloud 上的也要拉
        opt.deliveryMode = .highQualityFormat
        opt.version = .current
        opt.isSynchronous = false

        var finished = false
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opt) { data, _, _, info in
            // 可能被回调多次（先给缩略图再给原图），只认第一次完整数据
            if finished { return }
            if let err = info?[PHImageErrorKey] as? Error {
                NSLog("loadData fail: %@", err.localizedDescription)
                finished = true
                return completion(nil)
            }
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                finished = true
                return completion(nil)
            }
            if let data = data, data.count > 0 {
                finished = true
                DispatchQueue.main.async { completion(data) }
            }
        }
    }
}
