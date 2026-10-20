// Reglages du test de faisabilite. JavaScript ES5 uniquement.

// Serveur de streaming Stremio sur le PC Windows (Stremio Desktop ou stremio-service).
var PC_SERVER = "http://192.168.0.16:11470";

var CINEMETA = "https://v3-cinemeta.strem.io";
var CINEMETA_HTTP = "http://v3-cinemeta.strem.io";

var MP4_H264 = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4";
var MKV_H264 = "https://test-videos.co.uk/vids/bigbuckbunny/mkv/720/Big_Buck_Bunny_720_10s_1MB.mkv";
var HLS_HTTPS = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8";
var HLS_HTTP = "http://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8";

// Fichier optionnel servi par le PC avec l'appli (apps/step0-test/media/test.mp4, non versionne).
// Permet de tester la lecture en HTTP simple, sans TLS.
var LOCAL_MP4 = "media/test.mp4";

// Les fichiers locaux de media/ sont generes par tools/make_test_media.sh (non versionnes).
// Source HEVC 1080p sur internet, sans son (Jellyfin, CC BY-SA 4.0).
var HEVC_1080_WEB = "https://repo.jellyfin.org/test-videos/SDR/HEVC%208bit/Test%20Jellyfin%201080p%20HEVC%208bit%203M.mp4";

// URL HLS transcodee en H.264/AAC stereo par le serveur de streaming (protocole de
// stremio-video/withStreamingServer, MIT, Smart Code OOD).
function hlsv2(mediaUrl, force, server) {
    var id = "fbx" + Math.floor(Math.random() * 1e9);
    var q = "mediaURL=" + encodeURIComponent(mediaUrl)
            + "&videoCodecs=h264&audioCodecs=aac&audioCodecs=mp3&maxAudioChannels=2";
    if (force)
        q += "&forceTranscoding=1";
    return (server || PC_SERVER) + "/hlsv2/" + id + "/master.m3u8?" + q;
}
