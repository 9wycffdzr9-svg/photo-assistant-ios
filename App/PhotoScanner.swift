//
//  PhotoScanner.swift
//  相册扫描：拿到权限之后，把系统相册里的照片和视频翻一遍，生成待上传清单。
//
//  2026-11-16 小鱼
//  要点：
//  1. iOS 的「已隐藏」相簿在拿到 .readWrite 完整权限后是能读到的——用 smartAlbum 里的 .smartAlbumSlidingWindow？不对，
//     是 .smartAlbumHidden 之外，「已隐藏」在 Photos 框架里没有独立 smart album 常量，
//     所以这里直接按「全部 assets」遍历，隐藏项目同样会出现在结果里。
//  2. 只要预览和缩略图也能算「拿到」，但我们要原图，用 PHImageManager.requestImageDataAndOrientation。
//  3. 增量：记住上次扫描的最后一个 creationDate，下次只取更新的。
//

import Foundation
import Photos
import UIKit

struct ScannedAsset {
    var localId: String          // PHAsset.localIdentifier，去重用
    var creationDate: Date?
    var mediaType: String        // "image" / "video"
    var filename: String
    var byteSize: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var data: Data?              // 读失败时为 nil
}

final class PhotoScanner {

    /// 请求权限。返回是否拿到「完整」权限（.authorized 且不是 limited）
    static func requestPermission(completion: @escaping (Bool, Bool) -> Void) {
        // 返回 (granted, limited)
        let handler: (PHAuthorizationStatus) -> Void = { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    completion(true, false)
                case .limited:
                    completion(true, true)
                case .denied, .restricted:
                    completion(false, false)
                default:
                    completion(false, false)
                }
            }
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization(handler)
        }
    }

    /// 当前权限状态，不弹框
    static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 扫一遍。since 为 nil 时扫全部。
    /// - Parameters:
    ///   - since: 只取这个时间之后创建的
    ///   - limit: 一次最多取多少（避免一次读太多内存）
    static func scan(since: Date?, limit: Int = 200,
                     progress: @escaping (Int, Int) -> Void,
                     completion: @escaping ([ScannedAsset]) -> Void) {

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let since = since {
            options.predicate = NSPredicate(format: "creationDate > %@", since as NSDate)
        }
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(with: options)
        let total = result.count
        var out: [ScannedAsset] = []
        out.reserveCapacity(total)

        let manager = PHImageManager.default()
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = false
        reqOptions.isNetworkAccessAllowed = true      // iCloud 里的也要拉下来
        reqOptions.deliveryMode = .highQualityFormat
        reqOptions.version = .current

        let group = DispatchGroup()

        result.enumerateObjects { asset, index, _ in
            group.enter()

            let mediaType = asset.mediaType == .video ? "video" : "image"
            let filename = asset.value(forKey: "filename") as? String ?? "asset_\(index)"

            // 视频用 requestAVAsset 太慢，这里先只取元数据，视频本体后续单拉
            if asset.mediaType == .video {
                let item = ScannedAsset(
                    localId: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    mediaType: mediaType,
                    filename: filename,
                    byteSize: 0,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    data: nil
                )
                out.append(item)
                progress(out.count, total)
                group.leave()
                return
            }

            manager.requestImageDataAndOrientation(for: asset, options: reqOptions) { data, _, _, info in
                defer { group.leave() }
                if let err = info?[PHImageErrorKey] as? Error {
                    // 读不到也记一条，后面看板上能看见「这张没拿到」
                    NSLog("PhotoScanner read fail: %@", err.localizedDescription)
                }
                let item = ScannedAsset(
                    localId: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    mediaType: mediaType,
                    filename: filename,
                    byteSize: data?.count ?? 0,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    data: data
                )
                out.append(item)
                progress(out.count, total)
            }
        }

        group.notify(queue: .global(qos: .utility)) {
            out.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            completion(out)
        }
    }

    /// 只报数量，不读文件——用来做「你有 N 张照片」的展示
    static func count() -> Int {
        PHAsset.fetchAssets(with: nil).count
    }
}
