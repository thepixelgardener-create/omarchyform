// Change the clipboard while each of the board's text fields is open, and count
// requests for what it holds. A field may ask which formats are on offer; it
// must never ask for the text itself. On Wayland that text comes from whichever
// client owns the clipboard, for as long as it cares to send, and Qt 6.12.0's
// TextInput asked for all of it on every change, with nobody pasting.
// prepare(step) opens one field at a time and names it. Nothing here pastes.
// Built and run by tests/clipboard.js; Qt's public headers are enough.
#include <QClipboard>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QMimeData>
#include <QQuickItem>
#include <QQuickView>
#include <QUrl>
#include <cstdio>

// The clipboard deletes the data it held when it is given new data, so the
// count lives outside any one of them.
static int reads = 0;

class CountingMimeData final : public QMimeData {
protected:
    QVariant retrieveData(const QString &format, QMetaType type) const override {
        ++reads;
        return QMimeData::retrieveData(format, type);
    }
};

static void settle(int ms)
{
    QElapsedTimer clock;
    clock.start();
    while (clock.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
}

static void change(QClipboard::Mode mode)
{
    auto *data = new CountingMimeData;
    data->setText(QStringLiteral("clipboard text that no field may read"));
    QGuiApplication::clipboard()->setMimeData(data, mode);
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc < 2) {
        std::fprintf(stderr, "usage: clipboard_watch scene.qml\n");
        return 2;
    }
    QQuickView view;
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (view.status() != QQuickView::Ready) {
        for (const auto &error : view.errors())
            std::fprintf(stderr, "%s\n", qPrintable(error.toString()));
        return 2;
    }
    view.show();
    settle(300);
    std::printf("Qt %s\n", qVersion());

    QObject *scene = view.rootObject();
    QClipboard *clipboard = QGuiApplication::clipboard();
    for (int step = 0;; ++step) {
        QVariant name;
        QMetaObject::invokeMethod(scene, "prepare", Q_RETURN_ARG(QVariant, name), Q_ARG(QVariant, step));
        if (name.toString().isEmpty())
            break;
        settle(100);
        reads = 0;
        for (int i = 0; i < 3; ++i) {
            change(QClipboard::Clipboard);
            if (clipboard->supportsSelection())
                change(QClipboard::Selection);
            settle(30);
        }
        if (reads != 0) {
            std::fprintf(stderr, "FAIL: %s: %d requests for the clipboard's contents on 3 changes\n",
                         qPrintable(name.toString()), reads);
            return 1;
        }
        std::printf("ok   %s\n", qPrintable(name.toString()));
    }

    // A count of zero means something only if a read would have shown in it.
    reads = 0;
    const QString text = clipboard->text();
    if (reads == 0 || text.isEmpty()) {
        std::fprintf(stderr, "FAIL: reading the clipboard was not counted, so nothing above was measured\n");
        return 1;
    }
    std::printf("CLIPBOARD_TESTS_PASSED\n");
    return 0;
}
