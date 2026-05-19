// AIChatView.swift
import SwiftUI

struct AIChatView: View {
    @EnvironmentObject var chatVM:   ChatViewModel
    @EnvironmentObject var healthVM: HealthKitViewModel
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                chatHeader
                Divider().background(Color.card)
                messageList
                inputBar
            }
        }
    }

    var chatHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.accent, .teal],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.white).font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Fitness Coach").font(.headline).foregroundColor(.white)
                    Text("HealthKitAgent · UIAgent · QAAgent")
                        .font(.caption2).foregroundColor(.accent)
                }
                Spacer()
                Circle().fill(Color.teal).frame(width: 8, height: 8)
                Text("Groq").font(.caption2).foregroundColor(.teal)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
        }
    }

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatVM.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if chatVM.isLoading {
                        TypingIndicator()
                    }
                }
                .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
            }
            .onAppear  { scrollProxy = proxy }
            .onChange(of: chatVM.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: chatVM.isLoading) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if let last = chatVM.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your AI coach…", text: $inputText)
                .padding(12)
                .background(Color.card)
                .cornerRadius(22)
                .foregroundColor(.white)
                .accentColor(.accent)

            Button {
                let text = inputText.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, !chatVM.isLoading else { return }
                inputText = ""
                chatVM.send(text: text, healthData: healthVM.asDict)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(colors: [.accent, .teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || chatVM.isLoading)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(Color.bg)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 50) }
            if !isUser {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.accent, .teal],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles").font(.caption2).foregroundColor(.white)
                }
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(isUser
                        ? AnyView(LinearGradient(colors: [.accent, .teal],
                                                 startPoint: .leading, endPoint: .trailing))
                        : AnyView(Color.card))
                    .cornerRadius(18)
                Text(timeString(message.time))
                    .font(.caption2).foregroundColor(.secondary)
            }
            if isUser {
                ZStack {
                    Circle().fill(Color.card).frame(width: 28, height: 28)
                    Image(systemName: "person.fill").font(.caption2).foregroundColor(.accent)
                }
            }
            if !isUser { Spacer(minLength: 50) }
        }
    }

    func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animate = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.accent, .teal],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles").font(.caption2).foregroundColor(.white)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animate ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.5)
                            .repeatForever().delay(Double(i) * 0.15), value: animate)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.card).cornerRadius(18)
            Spacer()
        }
        .onAppear { animate = true }
    }
}
