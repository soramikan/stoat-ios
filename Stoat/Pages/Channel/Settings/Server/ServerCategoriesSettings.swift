//
//  ServerCategoriesSettings.swift
//  Stoat
//

import SwiftUI
import Types
import ULID

struct ServerCategoriesSettings: View {
    @EnvironmentObject var viewState: ViewState

    @Binding var server: Server

    @State var categories: [Types.Category] = []
    @State var newCategoryName = ""
    @State var error: String?
    @State var isSaving = false
    @State var hasLoaded = false

    var uncategorisedChannels: [Channel] {
        let categorised = Set(categories.flatMap(\.channels))

        return server.channels
            .filter { !categorised.contains($0) }
            .compactMap { viewState.channels[$0] }
    }

    var hasChanges: Bool {
        categories != (server.categories ?? [])
    }

    func createCategory() {
        let title = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        categories.append(Types.Category(id: ULID(timestamp: Date.now).ulidString, title: title, channels: []))
        newCategoryName = ""
    }

    func saveCategories() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await viewState.http.editServer(
                server: server.id,
                edits: ServerEdit(categories: categories)
            ).get()

            server = updated
            viewState.servers[updated.id] = updated
            categories = updated.categories ?? []
            error = nil
        } catch let e {
            error = e.localizedDescription
        }
    }

    var body: some View {
        List {
            Section("Create Category") {
                HStack {
                    TextField("Category name", text: $newCategoryName)
                        .textInputAutocapitalization(.words)

                    Button("Create") {
                        createCategory()
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .listRowBackground(viewState.theme.background2)

            if let error {
                Section {
                    Text(verbatim: error)
                        .foregroundStyle(viewState.theme.error)
                }
                .listRowBackground(viewState.theme.background2)
            }

            Section("Categories - \(categories.count)") {
                ForEach($categories) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Category name", text: category.title)
                            .font(.headline)

                        let channels = category.wrappedValue.channels.compactMap { viewState.channels[$0] }

                        if channels.isEmpty {
                            Text("No channels")
                                .font(.caption)
                                .foregroundStyle(viewState.theme.foreground2)
                        } else {
                            ForEach(channels, id: \.id) { channel in
                                ChannelIcon(channel: channel, initialSize: (14, 14), frameSize: (20, 20))
                                    .font(.subheadline)
                                    .foregroundStyle(viewState.theme.foreground2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    categories.remove(atOffsets: indexSet)
                }
                .onMove { source, destination in
                    categories.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listRowBackground(viewState.theme.background2)

            if !uncategorisedChannels.isEmpty {
                Section("Uncategorised") {
                    ForEach(uncategorisedChannels, id: \.id) { channel in
                        ChannelIcon(channel: channel)
                    }
                }
                .listRowBackground(viewState.theme.background2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(viewState.theme.background)
        .navigationTitle("Categories")
        .toolbarBackground(viewState.theme.topBar.color, for: .automatic)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await saveCategories() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(!hasChanges || isSaving)
            }

            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .task {
            if !hasLoaded {
                categories = server.categories ?? []
                hasLoaded = true
            }
        }
    }
}
