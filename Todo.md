# Todo

## Recently Completed ✓

- [x] **iCloud sync implementation** - switched to UIDocument for reliable cross-device sync
- [x] **Conflict resolution fix** - properly mark all conflict versions as resolved (prevents quota issues)
- [x] **Code comments audit** - improved all comments to explain WHY not just WHAT
- [x] **Cross-platform UI fixes** - platform-aware padding and gradients for iPhone/iPad/macOS
- [x] **Scroll behavior** - fixed arrow key navigation on macOS with cursor tracking
- [x] **Fix struct name** - renamed to ScrapsApp (matches app name)
- [x] **Typing lag fix** - removed redundant TextLineManager (was causing sync disk I/O on every keystroke)
- [x] **Smart regex processing** - only processes changed lines instead of entire document
- [x] **URL highlighting** - automatic detection and tap support
- [x] **Color scheme** - warmer accent colors implemented
- [x] **App naming** - settled on "Scraps"

## Performance Optimization

- [ ] Cache highlight patterns - avoid recreating UIColors on every init

## Code Quality

- [ ] Replace force-unwraps with proper error handling in TextHighlightManager.swift (regex compilation)
- [ ] Add tests for highlight/theme logic
- [ ] Implement UI tests (UITests.swift is currently empty)

## Features & Polish

- [ ] Make the initial launch to text input faster
	- currently slow due to
		- kb show animation
		- visible scroll to bottom; worse with longer text
- [ ] Design App Store assets and text
- [ ] Deploy to the App Store
- [ ] Fine-tune text color tinting with accent color?

# Ideas

What if text started to degrade after 1 day?
- Simple: get more faint over time
- Complex: per character or per word alpha?

What if clearing all text had a cool animation
- Text un-writes itself...
- Disappear char by char randomly

To implement text fading more easily
- track word count
- add gradient overlay same height as the text
- increase the opacity of the top of the gradient as word cound increases

What if it had automatic subtle datestamping on opening, like Drafts but all in one document?


