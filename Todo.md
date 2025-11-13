# Todo

## Performance Optimization

- [ ] Cache highlight patterns - avoid recreating UIColors on every init

## Code Quality

- [ ] Replace force-unwraps with proper error handling in TextHighlightManager.swift (regex compilation)
- [ ] Add tests for highlight/theme logic
- [ ] Implement UI tests (UITests.swift is currently empty)

## Bugs

- [ ] There's no way for the scraps list to update to another device while the app is open on that other device

## Features & Polish

- [x] Remove auto removal of empty scraps. If an empty scrap is created, it should persist and a second empty scrap should not be created.
- [ ] Add a way to delete a scrap / all scraps
- [ ] Add haptics on scrap creation
- [x] Try again to auto scroll to cursor with bottom padding

- [ ] Improve the separator design
- [ ] Make the initial launch to text input faster
	- currently slow due to
		- kb show animation
		- visible scroll to bottom; worse with longer text
- [ ] Fine-tune text color tinting with accent color?

## Deployment

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

What if it had automatic subtle datestamping on opening, like Drafts but all in one document?


