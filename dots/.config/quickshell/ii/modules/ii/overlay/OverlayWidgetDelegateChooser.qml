pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.modules.ii.overlay.crosshair
import qs.modules.ii.overlay.volumeMixer
import qs.modules.ii.overlay.photoSlideshow
import qs.modules.ii.overlay.fpsLimiter
import qs.modules.ii.overlay.googleCalendar
import qs.modules.ii.overlay.macClock
import qs.modules.ii.overlay.macCalendar
import qs.modules.ii.overlay.recorder
import qs.modules.ii.overlay.resources
import qs.modules.ii.overlay.notes

DelegateChooser {
    id: root
    role: "identifier"

    DelegateChoice { roleValue: "crosshair"; Crosshair {} }
    DelegateChoice { roleValue: "fpsLimiter"; FpsLimiter {} }
    DelegateChoice { roleValue: "googleCalendar"; GoogleCalendar {} }
    DelegateChoice { roleValue: "macClock"; MacClock {} }
    DelegateChoice { roleValue: "macCalendar"; MacCalendar {} }
    DelegateChoice { roleValue: "notes"; Notes {} }
    DelegateChoice { roleValue: "photoSlideshow"; PhotoSlideshow {} }
    DelegateChoice { roleValue: "recorder"; Recorder {} }
    DelegateChoice { roleValue: "resources"; Resources {} }
    DelegateChoice { roleValue: "volumeMixer"; VolumeMixer {} }
}
