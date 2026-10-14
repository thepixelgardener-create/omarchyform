// Private compositor and finite provider for tests/wayland.py. Never use a desktop socket.
#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QQuickItem>
#include <QQuickView>
#include <QTimer>
#include <QWaylandCompositor>
#include <QWaylandOutput>
#include <QWaylandOutputMode>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandXdgShell>
#include <cstdio>

class Payload : public QMimeData {
public:
    QString mode;
    explicit Payload(QString m)
        : mode(m)
    {
        setText(QString(mode == "large" ? 1048577 : mode == "exact" ? 1048576 : 32, 'x'));
    }
    QVariant retrieveData(const QString& f, QMetaType t) const override
    {
        // Qt may serialize its own offer here; this is not a native receive.
        fprintf(stderr, "LOCAL_MIME %s\n", qPrintable(f));
        fflush(stderr);
        return QMimeData::retrieveData(f, t);
    }
};
int main(int argc, char** argv)
{
    if (qEnvironmentVariable("OMARCHYFORM_PRIVATE_WAYLAND") != "1"
        || qEnvironmentVariable("WAYLAND_DISPLAY") != "audit-0"
        || qEnvironmentVariableIsSet("WAYLAND_SOCKET")) {
        fprintf(stderr, "Run through tests/wayland.py on its private socket.\n");
        return 2;
    }
    QGuiApplication app(argc, argv);
    QString mode = argc > 1 ? argv[1] : "";
    QTimer::singleShot(25000, &app, [] {
        fprintf(stderr, "WATCHDOG\n");
        QCoreApplication::exit(9);
    });
    if (mode == "server") {
        QWaylandCompositor comp;
        comp.setSocketName("audit-0");
        comp.setUseHardwareIntegrationExtension(false);
        comp.setRetainedSelectionEnabled(false);
        comp.create();
        QWaylandOutput output(&comp, nullptr);
        QWaylandOutputMode om(QSize(800, 800), 60000);
        output.addMode(om, true);
        output.setCurrentMode(om);
        QWaylandXdgShell shell(&comp);
        QObject::connect(&shell, &QWaylandXdgShell::toplevelCreated, &app,
            [&](QWaylandXdgToplevel* top, QWaylandXdgSurface* xdg) {
                top->sendConfigure(QSize(800, 800),
                    QList<QWaylandXdgToplevel::State> { QWaylandXdgToplevel::ActivatedState });
                auto* s = xdg->surface();
                output.surfaceEnter(s);
                comp.defaultSeat()->setKeyboardFocus(s);
                QTimer::singleShot(200, s, [&, s] {
                    comp.defaultSeat()->setKeyboardFocus(s);
                    comp.defaultSeat()->sendKeyEvent(Qt::Key_Shift, true);
                    comp.defaultSeat()->sendKeyEvent(Qt::Key_Shift, false);
                });
            });
        QTimer frames;
        QObject::connect(&frames, &QTimer::timeout, &app, [&] {
            output.frameStarted();
            output.sendFrameCallbacks();
        });
        frames.start(16);
        fprintf(stderr, "SERVER_READY Qt %s\n", qVersion());
        return app.exec();
    }
    if (argc < 3 || (mode != "provider" && mode != "consumer"))
        return 2;
    QQuickView view;
    view.setSource(QUrl::fromLocalFile(argv[2]));
    if (view.status() != QQuickView::Ready)
        return 2;
    view.show();
    if (mode == "provider") {
        QString kind = argc > 3 ? argv[3] : "finite";
        QTimer offers;
        QObject::connect(&offers, &QTimer::timeout, &app, [kind] {
            QGuiApplication::clipboard()->setMimeData(new Payload(kind));
            fprintf(stderr, "OFFER\n");
            fflush(stderr);
        });
        offers.start(600);
        return app.exec();
    }
    int step = 0;
    QTimer states;
    QObject::connect(&states, &QTimer::timeout, &app, [&] {
        if (step == 13) {
            fprintf(stderr, "POSITIVE_CONTROL\n");
            fflush(stderr);
            QString s = QGuiApplication::clipboard()->text();
            fprintf(stderr, "POSITIVE_BYTES %lld\n", (long long)s.size());
            app.exit(s.size() == 32 ? 0 : 3);
            return;
        }
        QVariant label;
        if (!QMetaObject::invokeMethod(view.rootObject(), "prepare", Q_RETURN_ARG(QVariant, label),
                Q_ARG(QVariant, step++))
            || label.toString().isEmpty()) {
            app.exit(2);
            return;
        }
        fprintf(stderr, "STATE %s\n", qPrintable(label.toString()));
        fflush(stderr);
    });
    states.start(750);
    return app.exec();
}
