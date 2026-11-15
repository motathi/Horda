extends Node
## Conexão do modo cooperativo (autoload "Net"): salas por código e lobby.
## No navegador: WebRTC, com a troca de SDP/ICE pelo servidor público do PeerJS.
## No PC (e nos testes): ENet por IP/porta. A partida em si é sincronizada pelo "Coop".

signal lobby_changed
signal status_changed(text: String)
signal failed(reason: String)
signal joined                 # cliente conectado ao anfitrião
signal connection_lost(reason: String)

enum Mode { OFFLINE, HOST, CLIENT }
const MAX_PLAYERS := 4
const ENET_PORT := 24680
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ID_PREFIX := "horda-sala-"
const JOIN_TIMEOUT := 12.0
const ICE := {"iceServers": [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
	{"urls": ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443"], "username": "openrelayproject", "credential": "openrelayproject"},
]}

var mode: Mode = Mode.OFFLINE
var room_code: String = ""
var my_name: String = "Sobrevivente"
## peer_id -> {"name": String, "skin": String}
var players: Dictionary = {}
var in_game: bool = false

var _sig: PeerJSSignal
var _rtc: WebRTCMultiplayerPeer
var _conns: Dictionary = {}     # peer_id -> WebRTCPeerConnection
var _sig_of: Dictionary = {}    # peer_id -> id de sinalização do convidado
var _next_id: int = 2
var _host_sig_id: String = ""
var _join_wait: float = -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: _fail("Não foi possível conectar ao anfitrião."))
	multiplayer.server_disconnected.connect(func() -> void: _lost("O anfitrião saiu da partida."))

func is_online() -> bool:
	return mode != Mode.OFFLINE

func is_host() -> bool:
	return mode == Mode.HOST

func is_client() -> bool:
	return mode == Mode.CLIENT

func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1

func use_webrtc() -> bool:
	return OS.has_feature("web") or OS.get_cmdline_user_args().has("--webrtc")

# --- Criar / entrar ------------------------------------------------------------------

func host_room(player_name: String) -> void:
	leave()
	my_name = player_name
	mode = Mode.HOST
	players = {1: {"name": my_name, "skin": GameManager.hero_skin}}
	if use_webrtc():
		room_code = _random_code()
		_rtc = WebRTCMultiplayerPeer.new()
		_rtc.create_server()
		multiplayer.multiplayer_peer = _rtc
		_sig = PeerJSSignal.new()
		_sig.opened.connect(func() -> void: status_changed.emit("Sala criada! Código: %s" % room_code))
		_sig.message.connect(_on_sig_host)
		_sig.failed.connect(_fail)
		_sig.connect_as(ID_PREFIX + room_code.to_lower())
		status_changed.emit("Criando sala...")
	else:
		var enet := ENetMultiplayerPeer.new()
		var err := enet.create_server(ENET_PORT, MAX_PLAYERS - 1)
		if err != OK:
			_fail("Não foi possível abrir a porta %d (%s)." % [ENET_PORT, error_string(err)])
			return
		multiplayer.multiplayer_peer = enet
		room_code = _lan_address()
		status_changed.emit("Sala aberta. Outros jogadores entram com o IP: %s" % room_code)
	lobby_changed.emit()

## code: código da sala (navegador) ou IP do anfitrião (PC).
func join_room(code: String, player_name: String) -> void:
	leave()
	my_name = player_name
	mode = Mode.CLIENT
	code = code.strip_edges()
	if use_webrtc():
		room_code = code.to_upper()
		_host_sig_id = ID_PREFIX + room_code.to_lower()
		_rtc = WebRTCMultiplayerPeer.new()
		_sig = PeerJSSignal.new()
		_sig.opened.connect(func() -> void:
			_sig.send(_host_sig_id, {"kind": "join", "name": my_name})
			_join_wait = JOIN_TIMEOUT
			status_changed.emit("Procurando a sala %s..." % room_code))
		_sig.message.connect(_on_sig_client)
		_sig.failed.connect(_fail)
		_sig.connect_as("horda-j-%d%d" % [randi() % 100000, Time.get_ticks_usec() % 100000])
		status_changed.emit("Conectando...")
	else:
		room_code = code if code != "" else "127.0.0.1"
		var enet := ENetMultiplayerPeer.new()
		var err := enet.create_client(room_code, ENET_PORT)
		if err != OK:
			_fail("Endereço inválido (%s)." % error_string(err))
			return
		multiplayer.multiplayer_peer = enet
		status_changed.emit("Conectando a %s..." % room_code)

func leave() -> void:
	if _sig:
		_sig.close()
	_sig = null
	for c: WebRTCPeerConnection in _conns.values():
		c.close()
	_conns.clear()
	_sig_of.clear()
	_next_id = 2
	_join_wait = -1.0
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_rtc = null
	mode = Mode.OFFLINE
	players.clear()
	in_game = false
	room_code = ""

func _process(delta: float) -> void:
	if _sig:
		_sig.poll(delta)
	if _join_wait > 0.0:
		_join_wait -= delta
		if _join_wait <= 0.0:
			_fail("Sala %s não encontrada (ou cheia). Confira o código." % room_code)

# --- Sinalização WebRTC ----------------------------------------------------------------

func _new_conn(peer_id: int, sig_to: String) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize(ICE)
	conn.session_description_created.connect(func(type: String, sdp: String) -> void:
		conn.set_local_description(type, sdp)
		_sig.send(sig_to, {"kind": "sdp", "id": peer_id, "type": type, "sdp": sdp}, "OFFER" if type == "offer" else "ANSWER"))
	conn.ice_candidate_created.connect(func(mid: String, index: int, cand: String) -> void:
		_sig.send(sig_to, {"kind": "ice", "id": peer_id, "mid": mid, "index": index, "cand": cand}, "CANDIDATE"))
	return conn

func _on_sig_host(from_id: String, p: Dictionary) -> void:
	match str(p.get("kind", "")):
		"join":
			if in_game or players.size() >= MAX_PLAYERS:
				_sig.send(from_id, {"kind": "refused", "reason": "A partida já começou." if in_game else "Sala cheia (%d jogadores)." % MAX_PLAYERS})
				return
			var pid := _next_id
			_next_id += 1
			_sig_of[pid] = from_id
			var conn := _new_conn(pid, from_id)
			_conns[pid] = conn
			_rtc.add_peer(conn, pid)
			conn.create_offer()
			status_changed.emit("%s está entrando..." % str(p.get("name", "Jogador")))
		"sdp":
			var c := _conns.get(int(p.get("id", 0))) as WebRTCPeerConnection
			if c:
				c.set_remote_description(str(p.get("type", "answer")), str(p.get("sdp", "")))
		"ice":
			var c2 := _conns.get(int(p.get("id", 0))) as WebRTCPeerConnection
			if c2:
				c2.add_ice_candidate(str(p.get("mid", "")), int(p.get("index", 0)), str(p.get("cand", "")))

func _on_sig_client(_from_id: String, p: Dictionary) -> void:
	match str(p.get("kind", "")):
		"refused":
			_fail(str(p.get("reason", "Entrada recusada.")))
		"expire":
			_fail("Sala %s não encontrada. Confira o código." % room_code)
		"sdp":
			_join_wait = -1.0
			var pid := int(p.get("id", 0))
			if not _conns.has(1):
				_rtc.create_client(pid)
				multiplayer.multiplayer_peer = _rtc
				var conn := _new_conn(pid, _host_sig_id)
				_conns[1] = conn
				_rtc.add_peer(conn, 1)
			(_conns[1] as WebRTCPeerConnection).set_remote_description(str(p.get("type", "offer")), str(p.get("sdp", "")))
			status_changed.emit("Conectando ao anfitrião...")
		"ice":
			var c := _conns.get(1) as WebRTCPeerConnection
			if c:
				c.add_ice_candidate(str(p.get("mid", "")), int(p.get("index", 0)), str(p.get("cand", "")))

# --- Lobby -------------------------------------------------------------------------------

func _on_connected_to_server() -> void:
	_join_wait = -1.0
	_register.rpc_id(1, my_name, GameManager.hero_skin)
	status_changed.emit("Conectado! Aguardando o anfitrião começar.")
	joined.emit()

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var nm := str(players.get(id, {}).get("name", "Jogador"))
	players.erase(id)
	_conns.erase(id)
	_lobby.rpc(players)
	if in_game:
		Coop.remove_player(id)
		EventBus.notify("%s saiu da partida." % nm, Color(1, 0.6, 0.4))

@rpc("any_peer", "reliable")
func _register(player_name: String, skin: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_game or players.size() >= MAX_PLAYERS:
		_kick.rpc_id(id, "A partida já começou." if in_game else "Sala cheia.")
		return
	players[id] = {"name": player_name.left(16), "skin": skin}
	_lobby.rpc(players)
	status_changed.emit("%s entrou na sala." % player_name)

@rpc("authority", "call_local", "reliable")
func _lobby(list: Dictionary) -> void:
	players = list
	lobby_changed.emit()

@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	_fail(reason)

## Anfitrião: todos carregam o mesmo mundo (mesma semente) e começam juntos.
func start_game(difficulty: String) -> void:
	if not is_host():
		return
	in_game = true
	_start.rpc(randi() % 1000000, difficulty, players)

@rpc("authority", "call_local", "reliable")
func _start(seed_value: int, difficulty: String, list: Dictionary) -> void:
	players = list
	in_game = true
	GameManager.start_coop_game(difficulty, seed_value)

func player_name(id: int) -> String:
	return str(players.get(id, {}).get("name", "Jogador %d" % id))

func player_skin(id: int) -> String:
	return str(players.get(id, {}).get("skin", "hunter"))

func _fail(reason: String) -> void:
	var was_game := in_game
	leave()
	if was_game:
		connection_lost.emit(reason)
	failed.emit(reason)
	status_changed.emit(reason)

func _lost(reason: String) -> void:
	_fail(reason)

# --- Utilidades -------------------------------------------------------------------------

func _random_code() -> String:
	var s := ""
	for i in 5:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s

func _lan_address() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"
