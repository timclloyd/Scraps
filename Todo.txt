# Todo

## Performance Optimization
- [x] Fixed typing lag by removing redundant TextLineManager (was causing sync disk I/O on every keystroke)
- [ ] Smart regex processing - only process changed paragraph/region instead of entire document
- [ ] Cache highlight patterns - avoid recreating UIColors on every init

## Code Quality
- [ ] Fix struct name in CacheApp.swift: rename NotesApp to CacheApp
- [ ] Fix filename: remove leading space from " UITextViewWrapper.swift"
- [ ] Replace force-unwraps with proper error handling in TextHighlightManager.swift (regex compilation)
- [ ] Add tests for highlight/theme logic
- [ ] Implement UI tests (UITests.swift is currently empty)

## Features & Polish
- [/] Fine tune colour scheme
	- [x] Accent colours... gut feel is I want something warmer?
	- [ ] Tint the text slightly with accent colour?
- [x] Refactor so it's easier to read
- [/] Add tests
- [/] Rename app to Ideas ???
- [ ] Make the initial launch to text input faster - currently slow due to kb show animation
- [x] Try highlighting URLs and making them tappable
- [ ] Design App Store assets and text
- [ ] Deploy to the App Store

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
