import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    color: "#1e1e2e"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1e1e2e" }
            GradientStop { position: 1.0; color: "#181825" }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24

        Text {
            text: "Honor Arch"
            color: "#89b4fa"
            font.pixelSize: 42
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Hyprland"
            color: "#cba6f7"
            font.pixelSize: 18
            Layout.alignment: Qt.AlignHCenter
        }

        Login {
            id: login
            Layout.alignment: Qt.AlignHCenter
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 24
        text: "Arch Linux + Hyprland"
        color: "#a6adc8"
        font.pixelSize: 12
    }
}
