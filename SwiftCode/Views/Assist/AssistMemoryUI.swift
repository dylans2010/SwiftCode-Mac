//
//  AssistMemoryUI.swift
//  SwiftCode
//
//  Visual card rendered in Assist when memory is automatically or explicitly saved.
//  Informs the user of what knowledge was stored in UserMemory.md.
//

import SwiftUI

public struct AssistMemoryUI: View {
    public let key: String
    public let value: String
    public let category: String
    public var onManage: (() -> Void)? = nil

    @State private var showFullValue = false
    @State private var isShowingManageSheet = false

    public init(key: String, value: String, category: String = "General", onManage: (() -> Void)? = nil) {
        self.key = key
        self.value = value
        self.category = category
        self.onManage = onManage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Saved to Memory")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(category)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                            .foregroundStyle(.purple)
                    }

                    Text("UserMemory.md updated")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isShowingManageSheet = true
                    onManage?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "slider.horizontal.2.square")
                            .font(.system(size: 9))
                        Text("Manage")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(showFullValue ? nil : 2)
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.25), lineWidth: 1)
        )
        .sheet(isPresented: $isShowingManageSheet) {
            UserMemoryView()
        }
    }
}
