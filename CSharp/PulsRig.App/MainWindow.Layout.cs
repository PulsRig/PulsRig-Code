using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace PulsRig.App;

public partial class MainWindow
{
    // Bei hoher DPI bleibt das logische Layout mindestens 980 × 660 groß.
    // Nur wenn der Bildschirm kleiner ist, wird der Rahmen scrollbar.
    void FitWorkArea()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var area = System.Windows.Forms.Screen.FromHandle(handle).WorkingArea;
        var dpi = VisualTreeHelper.GetDpi(this);
        var width = area.Width / dpi.DpiScaleX;
        var height = area.Height / dpi.DpiScaleY;
        MinWidth = Math.Min(980, width);
        MinHeight = Math.Min(660, height);
        Width = Math.Min(Width, width);
        Height = Math.Min(Height, height);
        Left = Math.Clamp(Left, area.Left / dpi.DpiScaleX, Math.Max(area.Left / dpi.DpiScaleX, area.Right / dpi.DpiScaleX - Width));
        Top = Math.Clamp(Top, area.Top / dpi.DpiScaleY, Math.Max(area.Top / dpi.DpiScaleY, area.Bottom / dpi.DpiScaleY - Height));
        FitSurface();
    }

    void FitSurface()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var vertical = ActualHeight + 0.5 < 660;
        var horizontal = ActualWidth - (vertical ? SystemParameters.VerticalScrollBarWidth : 0) + 0.5 < 980;
        vertical |= ActualHeight - (horizontal ? SystemParameters.HorizontalScrollBarHeight : 0) + 0.5 < 660;
        horizontal |= ActualWidth - (vertical ? SystemParameters.VerticalScrollBarWidth : 0) + 0.5 < 980;
        Surface.VerticalScrollBarVisibility = vertical ? System.Windows.Controls.ScrollBarVisibility.Visible : System.Windows.Controls.ScrollBarVisibility.Disabled;
        Surface.HorizontalScrollBarVisibility = horizontal ? System.Windows.Controls.ScrollBarVisibility.Visible : System.Windows.Controls.ScrollBarVisibility.Disabled;
        Shell.Width = Math.Max(980, ActualWidth - (vertical ? SystemParameters.VerticalScrollBarWidth : 0));
        Shell.Height = Math.Max(660, ActualHeight - (horizontal ? SystemParameters.HorizontalScrollBarHeight : 0));
    }
}