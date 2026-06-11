//
//  ReportUserSheetView.swift
//  Stoat
//

import SwiftUI
import Types

struct ReportUserSheetView: View {
    @EnvironmentObject var viewState: ViewState

    @Binding var showSheet: Bool

    var user: User

    @State var userContext = ""
    @State var error: String?
    @State var reason: ContentReportPayload.ContentReportReason = .NoneSpecified
    @State var isSubmitting = false

    func submit() async {
        if reason == .NoneSpecified {
            error = "Please select a category"
        } else if userContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Please add a reason"
        } else {
            error = nil
        }

        guard error == nil else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let _ = try await viewState.http.reportUser(id: user.id, reason: reason, userContext: userContext).get()
            showSheet = false
        } catch let e {
            error = e.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .center, spacing: 6) {
                Text("Report user")
                    .font(.title)
                    .bold()

                Text(verbatim: user.display_name ?? user.username)
                    .foregroundStyle(viewState.theme.foreground2)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a category")
                    .font(.caption)

                Picker("Report reason", selection: $reason) {
                    ForEach(ContentReportPayload.ContentReportReason.allCases, id: \.rawValue) { reason in
                        Text(reason.rawValue)
                            .tag(reason)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Give us some detail")
                    .font(.caption)

                TextField("What's wrong...", text: $userContext, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(10)
                    .background(viewState.theme.background2, in: RoundedRectangle(cornerRadius: 8))
            }

            if let error {
                Text(verbatim: error)
                    .foregroundStyle(viewState.theme.error)
                    .font(.subheadline)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()

                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit")
                    }

                    Spacer()
                }
            }
            .padding()
            .background(viewState.theme.accent, in: RoundedRectangle(cornerRadius: 8))
            .disabled(isSubmitting)

            Spacer()
        }
        .padding(24)
        .background(viewState.theme.background)
    }
}

