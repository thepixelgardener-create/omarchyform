// A file let go on a window, delivered the way the platform delivers it: a
// drag and a drop carrying the file's address, into Qt's window system
// interface, which hands them to whichever DropArea is under the point. A QML
// test cannot do this. Its Drag.mimeData travels only with drags the platform
// runs, so a drag inside the window reaches a DropArea with no address at all.
//
// The scene says where each drop goes, with `prepare(step)`, and what went
// wrong, with `verdict()`. Built and run by tests/drop.js.
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QMimeData>
#include <QQuickItem>
#include <QQuickView>
#include <QUrl>
#include <qpa/qplatformdrag.h>
#include <qpa/qwindowsysteminterface.h>
#include <cstdio>

static void settle(int ms)
{
    QElapsedTimer clock;
    clock.start();
    while (clock.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc < 3) {
        std::fprintf(stderr, "usage: drop_inject scene.qml dropped-file\n");
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

    QObject *scene = view.rootObject();
    QMimeData file;
    file.setUrls({ QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])) });
    for (int step = 0;; ++step) {
        QVariant at;
        QMetaObject::invokeMethod(scene, "prepare", Q_RETURN_ARG(QVariant, at), Q_ARG(QVariant, step));
        const QVariantMap point = at.toMap();
        if (point.isEmpty())
            break;
        settle(50);
        const QPoint p(point.value("x").toInt(), point.value("y").toInt());
        QWindowSystemInterface::handleDrag(&view, &file, p, Qt::CopyAction, Qt::LeftButton, Qt::NoModifier);
        settle(20);
        QWindowSystemInterface::handleDrop(&view, &file, p, Qt::CopyAction, Qt::LeftButton, Qt::NoModifier);
        settle(20);
    }

    QVariant verdict;
    QMetaObject::invokeMethod(scene, "verdict", Q_RETURN_ARG(QVariant, verdict));
    if (!verdict.toString().isEmpty()) {
        std::fprintf(stderr, "FAIL: %s\n", qPrintable(verdict.toString()));
        return 1;
    }
    std::printf("DROP_TESTS_PASSED\n");
    return 0;
}
