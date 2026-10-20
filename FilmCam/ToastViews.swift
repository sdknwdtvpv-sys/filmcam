import SwiftUI
import UIKit
import CoreMotion
import AVKit

struct ToastBar<Actions: View>: View {
    let icon: String
    let iconTint: Color
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundColor(iconTint)
                Text(message)
                    .foregroundColor(CameraTheme.ink)
                    .font(CameraTheme.mono(13))
                actions()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(CameraTheme.bgDeep.opacity(0.9))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CameraTheme.hairline, lineWidth: 1))
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom))
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

/// 提示条上的文字按钮统一样式

struct ToastAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .foregroundColor(CameraTheme.amber)
            .font(CameraTheme.mono(13, weight: .semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct ToastVideoSaved: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "checkmark.circle.fill", iconTint: .green,
                 message: "视频已保存到相册") {
            ToastAction(title: "分享") { manager.openVideoShare() }
            ToastAction(title: "好") { manager.clearVideoSaved() }
        }
    }
}

struct ToastVideoBlocked: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "exclamationmark.triangle.fill", iconTint: CameraTheme.amber,
                 message: "视频未保存：请在设置中允许访问照片") {
            ToastAction(title: "去设置") { manager.openSystemSettings() }
            ToastAction(title: "好") { manager.dismissVideoSaveBlocked() }
        }
    }
}

struct ToastPhotoBlocked: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "exclamationmark.triangle.fill", iconTint: CameraTheme.amber,
                 message: "照片未保存：请在设置中允许访问照片") {
            ToastAction(title: "去设置") { manager.openSystemSettings() }
            ToastAction(title: "好") { manager.dismissPhotoSaveBlocked() }
        }
    }
}

struct ToastDoubleExposureFirst: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "1.circle.fill", iconTint: CameraTheme.amber,
                 message: "第一张已曝光 · 请拍第二张") {
            ToastAction(title: "好") { manager.clearDoubleExposureFirst() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            manager.clearDoubleExposureFirst()
        }
    }
}

// MARK: - 拍立得摇一摇显影
