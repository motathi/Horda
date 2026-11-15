class_name PeerJSSignal
extends RefCounted
## Sinalização WebRTC pelo servidor público do PeerJS (0.peerjs.com), sem servidor próprio.
## Só transporta mensagens JSON entre ids; o conteúdo (SDP/ICE/pedido de entrada) é nosso.
## Chame poll() todo quadro.

signal opened
signal message(from_id: String, payload: Dictionary)
signal failed(reason: String)

const URL := "wss://0.peerjs.com/peerjs?key=peerjs&id=%s&token=%s"
const HEARTBEAT := 5.0

var my_id: String = ""
var _ws := WebSocketPeer.new()
var _open: bool = false
var _hb: float = HEARTBEAT
var _closed_reported: bool = false

func connect_as(id: String) -> void:
	my_id = id
	var token := str(randi())
	var err := _ws.connect_to_url(URL % [id, token])
	if err != OK:
		failed.emit("Não foi possível conectar ao servidor de salas (%s)." % error_string(err))

## O servidor público só repassa mensagens no formato do PeerJS: nossos dados vão como
## texto JSON dentro de "candidate.candidate" de uma mensagem CANDIDATE.
func send(to_id: String, payload: Dictionary, _kind: String = "") -> void:
	if not _open:
		return
	var wrapped := {"candidate": {"candidate": JSON.stringify(payload), "sdpMid": "0", "sdpMLineIndex": 0}, "type": "data", "connectionId": "dc_horda"}
	_ws.send_text(JSON.stringify({"type": "CANDIDATE", "dst": to_id, "payload": wrapped}))

func close() -> void:
	_ws.close()
	_open = false

func is_open() -> bool:
	return _open

func poll(delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		if not _closed_reported and my_id != "":
			_closed_reported = true
			_open = false
			failed.emit("Conexão com o servidor de salas encerrada (%d)." % _ws.get_close_code())
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	_hb -= delta
	if _hb <= 0.0 and _open:
		_hb = HEARTBEAT
		_ws.send_text(JSON.stringify({"type": "HEARTBEAT"}))
	while _ws.get_available_packet_count() > 0:
		var txt := _ws.get_packet().get_string_from_utf8()
		var msg: Variant = JSON.parse_string(txt)
		if not msg is Dictionary:
			continue
		var t := str(msg.get("type", ""))
		match t:
			"OPEN":
				_open = true
				opened.emit()
			"ID-TAKEN":
				failed.emit("Código de sala em uso. Tente de novo.")
			"ERROR", "INVALID-KEY":
				failed.emit("Servidor de salas recusou a conexão.")
			"EXPIRE":
				message.emit(str(msg.get("src", "")), {"kind": "expire"})
			"OFFER", "ANSWER", "CANDIDATE":
				var p: Variant = msg.get("payload", {})
				if p is Dictionary and p.get("candidate") is Dictionary:
					var inner: Variant = JSON.parse_string(str((p["candidate"] as Dictionary).get("candidate", "")))
					if inner is Dictionary:
						message.emit(str(msg.get("src", "")), inner)
