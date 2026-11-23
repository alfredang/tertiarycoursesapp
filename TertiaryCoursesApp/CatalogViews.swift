import SwiftUI

/// Public non-WSQ course catalog of this site, grouped into collapsible categories.
struct CatalogView: View {
    /// True when pushed inside another NavigationStack (Account → Browse Courses).
    var embedded = false

    @EnvironmentObject private var catalog: CatalogStore
    @State private var selectedCategory = "All"
    @State private var searchText = ""
    /// Categories the user has collapsed. Sections start expanded.
    @State private var collapsed: Set<String> = []

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [Course] {
        catalog.courses.filter { c in
            (selectedCategory == "All" || c.category == selectedCategory)
                && (query.isEmpty || c.searchIndex.localizedCaseInsensitiveContains(query))
        }
    }

    private var sections: [(name: String, courses: [Course])] {
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return catalog.categories.compactMap { name in
            guard let list = grouped[name], !list.isEmpty else { return nil }
            return (name, list)
        }
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All categories").tag("All")
                        ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Text("\(filtered.count) course\(filtered.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if catalog.courses.isEmpty {
                    ProgressView("Loading courses…").frame(maxWidth: .infinity).padding(.top, 40)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No courses found", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try a different keyword or category.")
                    } actions: {
                        Button("Clear Filters") {
                            searchText = ""
                            selectedCategory = "All"
                        }
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(sections, id: \.name) { section in
                        CategorySection(
                            name: section.name,
                            courses: section.courses,
                            isExpanded: !query.isEmpty || !collapsed.contains(section.name),
                            toggle: {
                                if collapsed.contains(section.name) { collapsed.remove(section.name) } else { collapsed.insert(section.name) }
                            }
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.page)
        .pullToRefresh { await catalog.refresh() }
        .navigationTitle("Courses")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search courses")
        .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
        .brandToolbar()
        .onChange(of: catalog.courses) { _, _ in
            if selectedCategory != "All" && !catalog.categories.contains(selectedCategory) { selectedCategory = "All" }
        }
    }
}

enum CategoryIcon {
    static func name(_ category: String) -> String {
        switch category {
        case "Artificial Intelligence": "sparkles"
        case "Data & Analytics": "chart.xyaxis.line"
        case "Programming": "chevron.left.forwardslash.chevron.right"
        case "Cloud & DevOps": "cloud.fill"
        case "Cybersecurity": "lock.shield.fill"
        case "Digital Marketing": "megaphone.fill"
        case "Design & Media": "paintbrush.fill"
        case "Microsoft Office": "square.grid.2x2.fill"
        case "Business & Soft Skills": "briefcase.fill"
        case "Engineering & IoT": "cpu.fill"
        case "Quality & Compliance": "checkmark.seal.fill"
        default: "books.vertical.fill"
        }
    }
}

/// A collapsible category header plus its course cards.
struct CategorySection: View {
    let name: String
    let courses: [Course]
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: CategoryIcon.name(name))
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    Text(name).font(.headline).foregroundStyle(.primary)
                    Text("\(courses.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accentSoft, in: Capsule())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(courses.count) courses")
            .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")

            if isExpanded {
                ForEach(courses) { course in
                    NavigationLink(value: course) { CourseCard(course: course) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CourseCard: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CourseThumb(url: course.image)
                VStack(alignment: .leading, spacing: 5) {
                    Text(course.sku)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(course.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            Text(course.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                if !course.duration.isEmpty { Label(course.duration, systemImage: "clock") }
                Spacer(minLength: 10)
                if course.price > 0 { Label(Fmt.money(course.price, course.currency), systemImage: "tag") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct CourseDetailView: View {
    let course: Course

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image = course.image {
                    AsyncImage(url: image) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                InfoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(course.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(course.title).font(.title3.bold())
                        Text(course.summary)
                        Divider()
                        LabeledContent("Course code", value: course.sku)
                        if !course.duration.isEmpty {
                            LabeledContent("Duration", value: course.duration)
                        }
                        if course.price > 0 {
                            LabeledContent("Course fee", value: Fmt.money(course.price, course.currency)
                                + (Site.priceNote.isEmpty ? "" : " (\(Site.priceNote))"))
                        }
                    }
                }

                if let url = course.pageURL {
                    Link(destination: url) {
                        Label("View Schedule & Register", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .controlSize(.large)
                }

                Button {
                    openWhatsApp(number: Site.whatsApp, body: "\(Site.siteName) course enquiry\n\nCourse: \(course.title)\nCourse code: \(course.sku)")
                } label: {
                    Label("Enquire via WhatsApp", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(20)
        }
        .background(Theme.page)
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
