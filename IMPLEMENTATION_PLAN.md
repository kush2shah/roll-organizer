# Photo Collection Editing Progress Tracker - Implementation Plan

## Overview
Build a native macOS app to track photo editing progress across collections by scanning directories and detecting which RAW photos have been edited.

## User Requirements

### Core Functionality
- Browse file directory structure interactively
- Display editing progress percentage for each folder/collection
- Automatically scan folders to detect edited photos
- Dual view modes: Summary (percentage cards) + Detail (photo grid with thumbnails)

### Technology Stack
- **Platform:** macOS 13.0+ (Ventura)
- **Language:** Swift 5.9+ with SwiftUI
- **Architecture:** MVVM + Repository pattern
- **Build Tool:** Xcode

### UI/UX Philosophy
- **Finder-like interface:** Mirror macOS Finder's look and feel
- **System-native components:** Use native SwiftUI controls with system styling
- **Low-key wrapper:** Minimal, unobtrusive UI that feels like an extension of Finder
- **System settings pattern:** Follow macOS System Settings visual language
- **Native behaviors:** Standard macOS keyboard shortcuts, drag-drop, context menus

### Photo Detection Strategy (Priority Order)
1. **XMP sidecar files** (Primary) - e.g., `DSC_1234.NEF` + `DSC_1234.xmp`
2. **Format conversion** - e.g., `DSC_1234.NEF` → `DSC_1234.jpg` in same folder
3. **Version numbering** - e.g., `DSC_1234.NEF` → `DSC_1234-2.jpg`
4. **Naming patterns** - "edit" keyword in filename (e.g., `DSC_1234edit.jpg`)
5. **EXIF metadata** (Future) - Edit timestamps, software tags

**Important:** Detection logic must distinguish between:
- **Files with "edit" in filename** → Edited photo
- **Folders with "edits" in name** → Just a folder, not a detection signal
- Only file-level patterns should trigger edit detection, not folder names

### Target Photo Formats
- **Primary:** RAW files (CR2, NEF, ARW, DNG, etc.)
- **Secondary:** JPEG, TIFF, HEIC, PSD

### User Workflow Context
- Uses Lightroom CC/Capture One
- Exports to different formats (RAW → JPEG/TIFF)
- Sometimes uses version numbers (-2, -3)
- Sometimes includes "edit" in filenames

## Implementation Approach

**Strategy:** Core logic first, UI later
- Build and test PhotoScanner and detection engine first
- Add UI once backend is solid and tested
- Ensures robust foundation before visual polish

**Folder Scanning:** Non-recursive with subdirectory awareness
- Scan only the selected folder (not subdirectories)
- Detect and display count of subdirectories found
- User can navigate into subfolders and scan them individually
- Future: Add recursive scanning option

## Implementation Plan

### Phase 1: MVP Foundation (First Implementation)

#### 1.1 Project Setup
**Create Xcode project:**
- macOS App template with SwiftUI
- Enable App Sandbox with file access entitlements
- Configure security-scoped bookmarks for folder access
- Set up project structure with Models, Views, ViewModels, Services folders

**Critical files to create:**
- `RollOrganizerApp.swift` - App entry point
- `Info.plist` - File access permissions
- `RollOrganizer.entitlements` - Sandbox configuration

#### 1.2 Core Data Models
**Create domain models** (`/RollOrganizer/Models/`):

```swift
// Photo.swift - Represents a single photo file
struct Photo: Identifiable {
    let id: UUID
    let url: URL
    let fileName: String
    let fileType: PhotoFileType // RAW or edited
    var editStatus: EditStatus
    var editedVariants: [URL] // Detected edited versions
}

// EditStatus.swift - Edit detection result
enum EditStatus {
    case unedited
    case edited(method: DetectionMethod)

    enum DetectionMethod {
        case xmpSidecar, formatConversion, versioning, namingPattern
    }
}

// PhotoCollection.swift - Represents a folder
struct PhotoCollection: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    var photos: [Photo]
    var subDirectories: [URL] // Subdirectories found (not scanned)
    var progress: CollectionProgress
}

// CollectionProgress.swift - Progress calculation
struct CollectionProgress {
    let totalPhotos: Int
    let editedPhotos: Int
    var percentageEdited: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(editedPhotos) / Double(totalPhotos) * 100
    }
}

// PhotoFileType.swift - File type classification
enum PhotoFileType {
    static let rawExtensions = ["nef", "cr2", "cr3", "arw", "dng", "orf", "raf"]
    static let editedExtensions = ["jpg", "jpeg", "tif", "tiff", "png", "heic", "psd"]
}
```

#### 1.3 Edit Detection Engine
**Create detection service** (`/RollOrganizer/Detection/`):

Strategy pattern with priority-ordered detection methods:

```swift
// EditDetectionStrategy.swift
protocol EditDetectionStrategy {
    func detect(for rawFile: URL, in directory: URL) async -> Bool
}

// XMPSidecarDetector.swift - Check for .xmp file
// FormatConversionDetector.swift - Check for JPEG/TIFF with same basename
// VersioningDetector.swift - Regex for -2, -3, _v2 patterns
// NamingConventionDetector.swift - Search for "edit" keyword in FILES (not folders)

// EditDetectionEngine.swift - Coordinator
class EditDetectionEngine {
    private let strategies: [EditDetectionStrategy]
    func isEdited(_ file: URL, in directory: URL) async -> Bool
}
```

#### 1.4 Photo Scanner Service
**Create scanner** (`/RollOrganizer/Services/PhotoScanner.swift`):

```swift
actor PhotoScanner {
    func scanDirectory(_ url: URL) async throws -> PhotoCollection {
        // 1. Enumerate files with FileManager (shallow, non-recursive)
        // 2. Separate files from subdirectories
        // 3. Filter files for RAW formats
        // 4. For each RAW, run EditDetectionEngine
        // 5. Calculate progress
        // 6. Return PhotoCollection with subdirectory count
    }
}
```

**Key implementation details:**
- Use `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:)`
- Pre-fetch resource keys: `[.isRegularFileKey, .isDirectoryKey, .typeIdentifierKey, .fileSizeKey]`
- Skip hidden files and packages
- **Non-recursive:** Only scan immediate directory contents
- Track subdirectories found (display count to user)
- Use async/await for non-blocking scans

#### 1.5 User Interface (SwiftUI)
**Design Principle: Finder-Like, System-Native**

**RootView.swift** - Main navigation:
```swift
NavigationSplitView {
    SidebarView() // Finder-style sidebar
} content: {
    SummaryView() // File browser feel
} detail: {
    DetailView() // Photo grid (future)
}
```

**Visual Style Guidelines:**
- Use system colors: `.primary`, `.secondary`, `.tertiary`
- Native SF Symbols for icons
- Standard macOS spacing and padding
- System font (SF Pro)
- Native list/grid styles
- Toolbar with standard macOS appearance
- No custom gradients or heavy styling
- Subtle, minimal visual indicators

**SummaryView.swift** - Finder-like list/grid:
- Option to switch between List and Grid views (like Finder)
- Standard row height and spacing
- System-style disclosure triangles
- Native selection highlighting
- Column headers if in list mode

**CollectionCard.swift** / **CollectionRow.swift**:
- **List mode:** Folder icon, name, progress text, subdirectory count (like Finder list view)
- **Grid mode:** Large folder icon, name below, compact progress indicator
- System-standard folder icons from NSWorkspace
- Subtle progress indication (not flashy)
- Matches Finder's visual density

**SidebarView.swift** - Finder sidebar style:
- Standard sidebar background color
- Section headers ("Favorites", "Recent")
- Folder icons from system
- Standard list row style
- Bottom toolbar with "+" button to add folders
- Mimic Finder's sidebar spacing and typography

#### 1.6 ViewModel Layer
**Create view models** (`/RollOrganizer/ViewModels/`):

```swift
@MainActor
class RootViewModel: ObservableObject {
    @Published var selectedCollection: PhotoCollection?
    @Published var visibleCollections: [PhotoCollection] = []
    @Published var isScanning: Bool = false

    private let scanner: PhotoScanner

    func selectFolder() async {
        // Open NSOpenPanel
        // Scan directory
        // Update visibleCollections
    }

    func refresh() async {
        // Re-scan current collection
    }
}
```

#### 1.7 Folder Access & Bookmarks
**Create bookmark manager** (`/RollOrganizer/Services/BookmarkManager.swift`):

```swift
class BookmarkManager {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> URL
    func accessSecuredResource<T>(_ url: URL, work: () throws -> T) throws -> T
}
```

Store bookmarks in UserDefaults for persistent access across launches.

### Phase 2: Enhanced Features

#### 2.1 Thumbnail Generation
**Create thumbnail service** (`/RollOrganizer/Services/ThumbnailGenerator.swift`):

Three-tier approach:
1. QuickLook (best for RAW files)
2. EXIF embedded thumbnails
3. Downsampled full image

Use NSCache for memory management (500 image limit, 100MB total).

#### 2.2 Detail View with Photo Grid
**Create detail view** (`/RollOrganizer/Views/Detail/`):
- LazyVGrid with photo thumbnails
- Status badges (✓ for edited, • for unedited)
- Show detection method on hover
- Lazy loading as user scrolls

#### 2.3 Performance Optimizations
- **Scan caching:** Save results to disk with modification date checks
- **Parallel scanning:** Use TaskGroup for multiple directories
- **Incremental updates:** Stream results to UI using AsyncStream
- **Thumbnail caching:** NSCache with size limits

#### 2.4 Additional UI Polish
- Keyboard shortcuts (Cmd+O for open folder)
- Context menus (Reveal in Finder)
- Search/filter bar
- Settings panel for detection preferences

### Phase 3: Future Enhancements
- Recursive folder scanning (scan subdirectories automatically)
- Navigate into subdirectories from UI
- EXIF metadata analysis
- Lightroom CC catalog integration
- Export reports (CSV, PDF)
- Statistics dashboard
- Watch folder for automatic updates

## Critical Files to Create (Priority Order)

### Essential for MVP:
1. **`/RollOrganizer/Services/PhotoScanner.swift`** - Core scanning logic
2. **`/RollOrganizer/Detection/EditDetectionEngine.swift`** - Edit detection coordinator
3. **`/RollOrganizer/Models/PhotoCollection.swift`** - Primary domain model
4. **`/RollOrganizer/ViewModels/RootViewModel.swift`** - Main app orchestration
5. **`/RollOrganizer/Views/Summary/CollectionCard.swift`** - Key UI component

### Supporting Files:
6. **`/RollOrganizer/App/RollOrganizerApp.swift`** - App entry point
7. **`/RollOrganizer/Detection/XMPSidecarDetector.swift`** - Primary detection method
8. **`/RollOrganizer/Detection/FormatConversionDetector.swift`** - Secondary detection
9. **`/RollOrganizer/Services/BookmarkManager.swift`** - Folder access persistence
10. **`/RollOrganizer/Views/Root/RootView.swift`** - Main navigation structure

## Technical Approach Highlights

### File Scanning Strategy
- Use `FileManager` with pre-fetched resource keys for performance
- Filter files by UTType extension matching
- Skip hidden files and packages automatically

### Edit Detection Logic
Each RAW file is checked against detectors in priority order:
1. Check for `{basename}.xmp` file (fastest, most reliable)
2. Check for `{basename}.{jpg|tiff|png|heic}` (format conversion)
3. Regex match for `{basename}-\d+` or `{basename}_v\d+` (versioning)
4. Substring match for "edit" in any **filename** (naming convention)

Stop at first match and record detection method.

**Critical:** Only check file names, never folder/directory names. User may have folders called "edits" or "edited" which should not trigger detection.

### Performance Targets
- Scan 100 photos in < 1 second
- Handle 10,000+ photo libraries
- Responsive UI during scanning (async/await)
- Thumbnail generation < 100ms per image

### macOS Integration
- Security-scoped bookmarks for sandboxed folder access
- QuickLook framework for RAW thumbnail generation
- NSOpenPanel for native folder picker
- Native SwiftUI controls and styling

## Development Workflow

```bash
# Create Xcode project
# File → New → Project → macOS → App
# Interface: SwiftUI, Language: Swift

# Enable sandbox and file access in entitlements:
# com.apple.security.app-sandbox = true
# com.apple.security.files.user-selected.read-only = true
# com.apple.security.files.bookmarks.app-scope = true

# Build and run
# Cmd+R in Xcode
```

## Testing Strategy
- Unit tests for each detection strategy
- Mock FileManager for deterministic tests
- Test with sample RAW files and various naming patterns
- Performance tests for large directories (1,000+ photos)

## Implementation Order

### Stage 1: Core Logic & Testing (Backend-First)
1. Create Xcode project with proper structure
2. Implement data models (Photo, PhotoCollection, EditStatus, etc.)
3. Implement detection strategies (XMP, format conversion, versioning, naming)
4. Implement EditDetectionEngine with priority ordering
5. Implement PhotoScanner with non-recursive scanning
6. Write unit tests for all detection strategies
7. Test with sample RAW files and various naming patterns

### Stage 2: User Interface (Frontend)
8. Create RootViewModel to orchestrate logic
9. Build RootView with NavigationSplitView structure
10. Build Finder-style SidebarView (standard macOS sidebar)
11. Build SummaryView with List/Grid toggle (like Finder views)
12. Build CollectionRow/Card components with system styling
13. Use NSWorkspace for system folder icons
14. Match macOS System Settings visual patterns
15. Integrate BookmarkManager for folder persistence
16. Wire up UI to backend services

**UI Reference:** Model after Finder and System Settings for:
- Color scheme and typography
- Icon usage and sizing
- Spacing and layout
- List/grid view patterns
- Sidebar organization

### Stage 3: Polish & Refinement
17. Add thumbnail generation
18. Add detail view with photo grid
19. Add performance optimizations (caching, parallel scanning)
20. Add keyboard shortcuts and context menus

## Success Criteria
✓ **Backend:** PhotoScanner correctly identifies RAW files and detects edits
✓ **Backend:** All detection strategies work and tests pass (including folder name edge cases)
✓ **Backend:** Naming detection only checks files, never folders (handles "edits" folder correctly)
✓ **Backend:** Non-recursive scanning with subdirectory tracking
✓ **UI:** Looks and feels like native Finder/System Settings
✓ **UI:** Uses system-standard components and styling
✓ **UI:** User can browse and select a folder naturally
✓ **UI:** Summary view displays accurate percentage and subdirectory count
✓ **UI:** Minimal, unobtrusive interface (low-key wrapper feel)
✓ **Performance:** Scan completes in reasonable time (< 5s for 1,000 photos)
✓ **Performance:** UI remains responsive during scanning
