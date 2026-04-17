import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var searchText = ""
    
    var filteredProjects: [Project] {
        let activeProjects = projects.filter { !$0.isArchived }
        if searchText.isEmpty {
            return activeProjects
        } else {
            return activeProjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.code.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var filteredArchivedProjects: [Project] {
        let archivedProjects = projects.filter { $0.isArchived }
        if searchText.isEmpty {
            return archivedProjects
        } else {
            return archivedProjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.code.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredProjects) { project in
                NavigationLink(destination: ProjectDetailView(project: project)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(project.name)
                                .font(.headline)
                            Text(project.code)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        StatusIcon(status: project.status)
                    }
                }
            }

            if !filteredArchivedProjects.isEmpty {
                Section("Archivés") {
                    ForEach(filteredArchivedProjects) { project in
                        NavigationLink(destination: ProjectDetailView(project: project)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(project.name)
                                        .font(.headline)
                                    Text(project.code)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                StatusIcon(status: project.status)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Projets")
    }
}

struct StatusIcon: View {
    let status: String
    
    var body: some View {
        Circle()
            .fill(colorForStatus(status))
            .frame(width: 12, height: 12)
    }
    
    private func colorForStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        default: return .gray
        }
    }
}
