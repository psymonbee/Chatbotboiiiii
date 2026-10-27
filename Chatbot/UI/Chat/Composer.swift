import PhotosUI
import SwiftUI

/// "Send message…" with mic and attach buttons. The mic opens voice mode; it turns into
/// send while there's something to send, and stop while a reply is streaming.
struct Composer: View {
    @Bindable var session: ChatSession
    var onVoice: () -> Void

    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if !session.pendingAttachments.isEmpty {
                pendingStrip
            }
            if let error = session.attachmentError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.pink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            HStack(alignment: .bottom, spacing: 6) {
                TextField("Send message…", text: $session.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.vertical, 9)
                    #if os(macOS)
                    .onSubmit { session.send() }
                    #endif

                trailingButton
                attachMenu
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) {
            let items = photoItems
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: AttachmentLoader.importableTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await session.attach(urls: urls) }
            case .failure(let error): session.attachmentError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if session.isGenerating {
            circleButton("stop.fill", label: "Stop", filled: true) { session.stop() }
        } else if session.canSend {
            circleButton("arrow.up", label: "Send", filled: true) {
                session.send()
            }
            .keyboardShortcut(.return, modifiers: .command)
        } else {
            circleButton("mic", label: "Voice mode", filled: false, action: onVoice)
        }
    }

    private var attachMenu: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { showPhotos = true }
                .disabled(!session.acceptsImages)
            Button("Files", systemImage: "doc") { showFiles = true }
            if !session.acceptsImages {
                Text("\(session.settings.model) can't view images")
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 20, weight: .regular))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .foregroundStyle(.white.opacity(0.9))
        .accessibilityLabel("Attach")
        .fixedSize()
    }

    private func circleButton(_ symbol: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: filled ? 15 : 19, weight: filled ? .bold : .regular))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background {
                    if filled { Circle().fill(Theme.gradient) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var pendingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.pendingAttachments) { attachment in
                    AttachmentThumb(attachment: attachment, size: 64)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                session.removePending(attachment)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.7))
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Remove \(attachment.filename)")
                        }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                await session.attach(imageData: data, filename: "Photo \(index + 1).jpg")
            } catch {
                session.attachmentError = error.localizedDescription
            }
        }
    }
}
