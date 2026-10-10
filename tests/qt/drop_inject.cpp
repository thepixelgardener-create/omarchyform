// Deliver foreign offers through Qt's actual window-system drag entry points.
// The production board must reject them without requesting payload bytes.
// prepare(step) selects a pane/layout; verdict() checks that no import ran.
// Built and run by tests/drop.js, without a hostile stream or real user data.
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QMimeData>
#include <QQuickItem>
#include <QQuickView>
#include <QUrl>
#include <qpa/qplatformdrag.h>
#include <qpa/qwindowsysteminterface.h>
#include <cstdio>

// Count requests for payload bytes, not MIME metadata. A real hostile sender
// could stream forever here; the application must never request these bytes.
class CountingMimeData final : public QMimeData {
public:
    mutable int reads = 0;
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
    CountingMimeData file;
    file.setUrls({ QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])) });
    file.setText("foreign drag text must never be retrieved");
    for (int step = 0;; ++step) {
        QVariant at;
        QMetaObject::invokeMethod(scene, "prepare", Q_RETURN_ARG(QVariant, at), Q_ARG(QVariant, step));
        const QVariantMap point = at.toMap();
        if (point.isEmpty())
            break;
        settle(50);
        const QPoint p(point.value("x").toInt(), point.value("y").toInt());
        const auto drag = QWindowSystemInterface::handleDrag(&view, &file, p, Qt::CopyAction, Qt::LeftButton, Qt::NoModifier);
        settle(20);
        const auto drop = QWindowSystemInterface::handleDrop(&view, &file, p, Qt::CopyAction, Qt::LeftButton, Qt::NoModifier);
        if (file.reads != 0 || drag.isAccepted() || drop.isAccepted()) {
            std::fprintf(stderr, "FAIL: external offer %d accepted or read (%d payload requests)\n", step, file.reads);
            return 1;
        }
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
