import QtQuick 2.15
QtObject {
    enum Status { UnknownStatus, NoMedia, Loading, Loaded, Stalled, Buffering, Buffered, EndOfMedia, InvalidMedia }
    enum State { StoppedState, PlayingState, PausedState }
    property string source: ""
    property bool autoPlay: false
    property int position: 0
    property int duration: 0
    property int status: 1
    property int playbackState: 0
    property bool seekable: false
    property string errorString: ""
    property int notifyInterval: 1000
    signal error(int error, string errorString)
    function play() {}
    function pause() {}
    function stop() {}
    function seek(p) {}
}
