//
//  CreateServer.swift
//  Stoat
//
//  Created by Angelo on 24/08/2024.
//

import Foundation
import SwiftUI

struct CreateServer: View {
    @EnvironmentObject var viewState: ViewState
    @Environment(\.dismiss) var dismiss

    @State var name: String = ""
    @State var description: String = ""
    @State var nsfw: Bool = false
    @State var isCreating: Bool = false
    @State var errorMessage: String?

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String? {
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    
    var body: some View {
        Form {
            Section {
                TextField("Server name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)

                Toggle("Mark as NSFW", isOn: $nsfw)
            } footer: {
                Text("Create a server with a default text channel and voice channel.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    create()
                } label: {
                    if isCreating {
                        ProgressView()
                    } else {
                        Text("Create Server")
                    }
                }
                .disabled(trimmedName.isEmpty || isCreating)
            }
        }
        .scrollContentBackground(.hidden)
        .background(viewState.theme.background)
        .navigationTitle("Create Server")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    func create() {
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        Task {
            let result = await viewState.http.createServer(
                name: trimmedName,
                description: trimmedDescription,
                nsfw: nsfw ? true : nil
            )

            await MainActor.run {
                isCreating = false

                switch result {
                    case .success(let response):
                        viewState.servers[response.server.id] = response.server
                        for channel in response.channels {
                            viewState.channels[channel.id] = channel
                            viewState.channelMessages[channel.id] = []
                        }
                        viewState.selectServer(withId: response.server.id)
                        dismiss()
                    case .failure:
                        errorMessage = "Unable to create server. Check your permissions and try again."
                }
            }
        }
    }
}
