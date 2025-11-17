вом# Contributing to LYWSD02 Clock Sync

First off, thank you for considering contributing to LYWSD02 Clock Sync! 🎉

This document provides guidelines for contributing to the project. Following these guidelines helps communicate that you respect the time of the developers managing and developing this open source project.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)

---

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code.

### Our Pledge

- **Be respectful** - Disagreement is fine, disrespect is not
- **Be collaborative** - We're all working toward the same goal
- **Be inclusive** - Everyone should feel welcome
- **Be patient** - Not everyone has the same experience level

---

## How Can I Contribute?

### 🐛 Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

**Bug Report Template:**
```markdown
**Description:**
Clear description of the bug

**Steps to Reproduce:**
1. Go to '...'
2. Tap on '...'
3. Scroll down to '...'
4. See error

**Expected Behavior:**
What you expected to happen

**Actual Behavior:**
What actually happened

**Environment:**
- iOS/macOS version:
- Device model:
- App version:
- LYWSD02 firmware (if known):

**Screenshots:**
If applicable

**Additional Context:**
Any other relevant information
```

---

### 💡 Suggesting Features

Feature suggestions are welcome! Please provide:

1. **Use case** - Why is this feature needed?
2. **Proposed solution** - How should it work?
3. **Alternatives** - Other solutions you've considered
4. **Examples** - Similar features in other apps

**Feature Request Template:**
```markdown
**Feature Description:**
Clear description of the feature

**Problem It Solves:**
What user problem does this address?

**Proposed Implementation:**
How it should work (optional)

**Mockups/Examples:**
Visual examples if applicable
```

---

### 🔧 Code Contributions

We love code contributions! Here's how to get started:

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create a branch** for your feature/fix
4. **Make your changes**
5. **Test** thoroughly
6. **Submit a pull request**

---

## Development Setup

### Prerequisites

- macOS 13.0+ (for macOS development)
- Xcode 15.0+
- Swift 5.9+
- Git
- LYWSD02 device for testing

### Initial Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/LYWSD02-Clock-Sync.git
cd LYWSD02-Clock-Sync

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/LYWSD02-Clock-Sync.git

# Open in Xcode
open "LYWSD02 Clock Sync.xcodeproj"
```

### Build & Run

1. Select target (iOS or macOS)
2. Press `⌘R` to build and run
3. Grant Bluetooth permissions when prompted

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme "LYWSD02 Clock Sync (iOS)" \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Or use Xcode: Product > Test (⌘U)
```

---

## Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

#### General Rules

- **Line length:** 120 characters max
- **Indentation:** 4 spaces (no tabs)
- **Naming:** 
  - Types: `PascalCase`
  - Variables/functions: `camelCase`
  - Constants: `camelCase` (not SCREAMING_SNAKE_CASE)

#### Code Style Examples

```swift
// ✅ Good
func synchronizeDeviceTime(to target: Date) throws {
    guard hasTimeSupport else {
        throw BLEError.characteristicNotFound
    }
    
    let timestamp = Int(target.timeIntervalSince1970)
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
}

// ❌ Bad
func sync_time(t:Date)->Void{
if has_time{
peripheral.writeValue(d,for:c,type:.withResponse)}}
```

### Documentation

All public APIs must be documented:

```swift
/// Synchronizes the device time to the specified date.
///
/// The time is encoded with the current timezone offset and written
/// to the device's time characteristic.
///
/// - Parameter target: The target date to sync to
/// - Throws: `BLEError.characteristicNotFound` if device doesn't support time sync
/// - Throws: `BLEError.invalidData` if target date is out of valid range
func syncTime(target: Date) throws {
    // Implementation
}
```

### Error Handling

```swift
// ✅ Good - Proper error handling
do {
    try device.syncTime(target: Date())
} catch BLEError.characteristicNotFound {
    logger.error("Device doesn't support time sync")
} catch {
    logger.error("Sync failed: \(error)")
}

// ❌ Bad - Force unwrap, ignoring errors
try! device.syncTime(target: Date())
```

### Concurrency

Use modern Swift concurrency:

```swift
// ✅ Good - Async/await
Task { @MainActor in
    await fetchData()
    updateUI()
}

// ❌ Bad - Completion handlers for new code
fetchData { data in
    DispatchQueue.main.async {
        self.updateUI()
    }
}
```

### SwiftUI Best Practices

```swift
// ✅ Good - Small, focused views
struct TemperatureView: View {
    let temperature: Double?
    
    var body: some View {
        if let temp = temperature {
            Text("\(temp, specifier: "%.1f")°C")
        } else {
            ProgressView()
        }
    }
}

// ❌ Bad - Massive view with everything
struct MassiveView: View {
    var body: some View {
        VStack {
            // 500 lines of code
        }
    }
}
```

---

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

#### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding tests
- `chore`: Maintenance tasks

#### Examples

```
feat(bluetooth): add connection timeout handling

Implements 10-second timeout for BLE connections to prevent
indefinite hangs. Automatically cancels connection and logs
error if device doesn't respond.

Closes #42
```

```
fix(ui): prevent crash on invalid sensor data

Added validation for temperature and humidity ranges before
updating UI. Values outside expected ranges are now logged
and ignored rather than causing crashes.

Fixes #87
```

### Commit Best Practices

- ✅ Write in present tense ("add feature" not "added feature")
- ✅ Keep subject line under 50 characters
- ✅ Separate subject from body with blank line
- ✅ Reference issues in footer
- ✅ Make atomic commits (one logical change per commit)
- ❌ Don't commit commented-out code
- ❌ Don't commit debug print statements
- ❌ Don't mix formatting changes with logic changes

---

## Pull Request Process

### Before Submitting

- [ ] Code compiles without warnings
- [ ] All tests pass
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Changelog updated (if applicable)
- [ ] No merge conflicts

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
How was this tested?

## Checklist
- [ ] Code follows project style
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Tests added/updated

## Screenshots
If UI changes

## Related Issues
Fixes #123
```

### Review Process

1. **Automated checks** must pass (if configured)
2. **At least one approval** from maintainers required
3. **All comments** must be resolved
4. **Squash and merge** preferred for clean history

### What Happens After Submit?

- Maintainers will review within 1 week
- You may be asked to make changes
- Once approved, a maintainer will merge
- Your contribution will be credited in release notes

---

## Issue Reporting

### Bug Reports

Use the **Bug Report** template. Include:

- Clear, descriptive title
- Detailed steps to reproduce
- Expected vs actual behavior
- Environment information
- Screenshots/logs if applicable

**Priority Labels:**
- `critical` - App crashes, data loss
- `high` - Major functionality broken
- `medium` - Inconvenient but workarounds exist
- `low` - Minor issues, cosmetic

### Feature Requests

Use the **Feature Request** template. Include:

- Clear description of feature
- Use case / problem it solves
- Proposed implementation (optional)
- Examples from other apps (if applicable)

---

## Development Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `refactor/description` - Code refactoring
- `docs/description` - Documentation updates

**Examples:**
```
feature/connection-timeout
fix/sensor-data-validation
refactor/bluetooth-client
docs/api-documentation
```

### Workflow Example

```bash
# 1. Update your fork
git checkout main
git fetch upstream
git merge upstream/main

# 2. Create feature branch
git checkout -b feature/my-awesome-feature

# 3. Make changes, commit often
git add .
git commit -m "feat: add awesome feature"

# 4. Push to your fork
git push origin feature/my-awesome-feature

# 5. Create pull request on GitHub
```

---

## Testing Guidelines

### Unit Tests

Required for:
- Business logic
- Data parsing/encoding
- Validation functions
- Error handling

```swift
import XCTest
@testable import LYWSD02_Clock_Sync

class BinUtilsTests: XCTestCase {
    func testPackUnpackRoundTrip() {
        let original = [42, 100]
        let packed = pack("<HH", original)
        let unpacked = try! unpack("<HH", packed)
        
        XCTAssertEqual(unpacked[0] as! Int, 42)
        XCTAssertEqual(unpacked[1] as! Int, 100)
    }
}
```

### Integration Tests

Test interactions between components:
- BLE connection flow
- Auto-sync behavior
- Reconnection logic

### UI Tests

For critical user flows:
- Device discovery
- Time synchronization
- History viewing

---

## Code Review Checklist

As a **PR author**, verify:

- [ ] Code is self-documenting or well-commented
- [ ] No hardcoded values (use constants)
- [ ] Error cases handled
- [ ] No force unwraps (`!`)
- [ ] No commented-out code
- [ ] No debug print statements
- [ ] Thread safety considered
- [ ] Memory leaks prevented

As a **reviewer**, check:

- [ ] Code does what PR claims
- [ ] No security vulnerabilities
- [ ] Follows project conventions
- [ ] Edge cases handled
- [ ] Tests are meaningful
- [ ] Documentation accurate

---

## Getting Help

### Resources

- 📖 [README.md](./README.md) - Project overview
- 📚 [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) - API reference
- 🔍 [CODE_REVIEW_REPORT.md](./CODE_REVIEW_REPORT.md) - Code quality insights

### Communication

- **GitHub Issues** - Bug reports, feature requests
- **GitHub Discussions** - Questions, ideas
- **Email** - security@example.com (for security issues only)

### Common Questions

**Q: Where should I start?**  
A: Look for issues labeled `good first issue` or `help wanted`

**Q: How long until my PR is reviewed?**  
A: Usually within 1 week. If longer, feel free to ping.

**Q: Can I work on multiple issues at once?**  
A: Yes, but use separate branches for each.

**Q: What if I disagree with feedback?**  
A: Discuss politely. Maintainers have final say.

---

## Recognition

Contributors are recognized in:

- Release notes
- README contributors section
- Git commit history

Significant contributions may earn you:
- Commit access
- Maintainer status
- Project leadership roles

---

## License

By contributing, you agree that your contributions will be licensed under the project's MIT License.

---

## Thank You! 🙏

Your contributions make this project better for everyone. We appreciate your time and effort!

**Happy coding!** 🚀
