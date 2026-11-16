# Apple platform API references

Scribbit uses public Apple APIs to locate the camera-safe screen area, observe
pointer movement, present the editor, animate its silhouette and save its file.
These links document the platform facilities used by the app; they do not imply
Apple authored Scribbit or published its particular animation parameters.

## Screen geometry and notch placement

| API | Use in Scribbit |
| --- | --- |
| [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) | Reserve the screen area obscured by the camera housing |
| [NSScreen.auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea) | Locate usable screen space beside the camera housing |
| [NSScreen.auxiliaryTopRightArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea) | Combine the auxiliary areas to determine camera width |

The app computes its own trigger and content geometry from these values. On
unnotched displays it provides a top-center trigger rather than requiring a
physical camera cutout. See [geometry and lifecycle](ARCHITECTURE.md).

## Presentation and motion

- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel) hosts the
  editor without turning it into a normal document window.
- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover) presents
  transient settings anchored to native expanded gear/collapsed chevron controls,
  without a status item.
- [NSAlert.beginSheetModal](https://developer.apple.com/documentation/appkit/nsalert/beginsheetmodal(for:completionhandler:))
  parents About to the elevated note panel. The native window delegate's sheet
  positioning callback supplies the camera-safe attachment rectangle.
- [CAShapeLayer](https://developer.apple.com/documentation/quartzcore/cashapelayer)
  masks a fixed-size presentation window with the attached silhouette.
- [CAKeyframeAnimation](https://developer.apple.com/documentation/quartzcore/cakeyframeanimation)
  animates the sampled shape path.

The oscillator sampling, spring parameters, hover deadlines and content timing
are Scribbit configuration, not values attributed to Apple's documentation.
See [motion design](NOTCH-UX.md) for the current settings.

## Events, files and login

- [NSEvent.addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)) observes mouse movement outside the app.
- [NSEvent.addLocalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)) handles the app's own events.
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator) coordinates file access with participating applications.
- [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) manages user-approved launch at login.

## Reuse boundary

The current package has no third-party runtime dependencies or bundled reference
checkouts. Review licenses and retain required notices before importing any
third-party implementation or assets. This API catalog is not legal clearance
for source reuse and does not assert clean-room development.

### File observation

- [Apple Dispatch Sources](https://developer.apple.com/library/archive/documentation/General/Conceptual/ConcurrencyProgrammingGuide/GCDWorkQueues/GCDWorkQueues.html): file-system sources, asynchronous/coalesced delivery and cancellation-handler descriptor ownership.
- [Apple File System Events guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html): advisory nature of change notification. FSEvents is not a runtime dependency.

The implementation uses public native DispatchSource APIs, not third-party watcher code.
