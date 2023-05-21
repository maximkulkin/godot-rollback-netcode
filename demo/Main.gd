extends Node2D

const DummyNetworkAdaptor = preload("res://addons/godot-rollback-netcode/DummyNetworkAdaptor.gd")

@onready var main_menu = $CanvasLayer/MainMenu
@onready var connection_panel = $CanvasLayer/ConnectionPanel
@onready var host_field = $CanvasLayer/ConnectionPanel/GridContainer/HostField
@onready var port_field = $CanvasLayer/ConnectionPanel/GridContainer/PortField
@onready var message_label = $CanvasLayer/MessageLabel
@onready var sync_lost_label = $CanvasLayer/SyncLostLabel
@onready var reset_button = $CanvasLayer/ResetButton

const LOG_FILE_DIRECTORY = 'user://detailed_logs'

var logging_enabled := true

func _ready() -> void:
	multiplayer.connect("peer_connected", _on_network_peer_connected)
	multiplayer.connect("peer_disconnected", _on_network_peer_disconnected)
	multiplayer.connect("server_disconnected", _on_server_disconnected)
	SyncManager.connect("sync_started", _on_SyncManager_sync_started)
	SyncManager.connect("sync_stopped", _on_SyncManager_sync_stopped)
	SyncManager.connect("sync_lost", _on_SyncManager_sync_lost)
	SyncManager.connect("sync_regained", _on_SyncManager_sync_regained)
	SyncManager.connect("sync_error", _on_SyncManager_sync_error)
	
	var cmdline_args = OS.get_cmdline_args()
	if "server" in cmdline_args:
		_on_ServerButton_pressed()
	elif "client" in cmdline_args:
		_on_ClientButton_pressed()
	
	if SyncReplay.active:
		main_menu.visible = false
		connection_panel.visible = false
		reset_button.visible = false

func _on_OnlineButton_pressed() -> void:
	connection_panel.popup_centered()
	SyncManager.reset_network_adaptor()

func _on_LocalButton_pressed() -> void:
	main_menu.visible = false
	$ServerPlayer.input_prefix = "player2_"
	SyncManager.network_adaptor = DummyNetworkAdaptor.new()
	SyncManager.start()

func _on_ServerButton_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(int(port_field.text), 1)
	multiplayer.multiplayer_peer = peer
	connection_panel.visible = false
	main_menu.visible = false

func _on_ClientButton_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(host_field.text, int(port_field.text))
	multiplayer.multiplayer_peer = peer
	connection_panel.visible = false
	main_menu.visible = false
	message_label.text = "Connecting..."

func _on_network_peer_connected(peer_id: int):
	$ServerPlayer.set_multiplayer_authority(1)
	if multiplayer.is_server():
		$ClientPlayer.set_multiplayer_authority(peer_id)
	else:
		$ClientPlayer.set_multiplayer_authority(multiplayer.get_unique_id())
	
	SyncManager.add_peer(peer_id)
	if multiplayer.is_server():
		message_label.text = "Starting..."
		# Give a little time to get ping data.
		await get_tree().create_timer(2.0).timeout
		SyncManager.start()

func _on_network_peer_disconnected(peer_id: int):
	message_label.text = "Disconnected"
	SyncManager.remove_peer(peer_id)

func _on_server_disconnected() -> void:
	_on_network_peer_disconnected(1)

func _on_SyncManager_sync_started() -> void:
	message_label.text = "Started!"
	
	if logging_enabled and not SyncReplay.active:
		DirAccess.make_dir_absolute(LOG_FILE_DIRECTORY)
		
		var datetime = Time.get_datetime_dict_from_system(true)
		var log_file_name = "%04d%02d%02d-%02d%02d%02d-peer-%d.log" % [
			datetime['year'],
			datetime['month'],
			datetime['day'],
			datetime['hour'],
			datetime['minute'],
			datetime['second'],
			multiplayer.get_unique_id(),
		]
		
		SyncManager.start_logging(LOG_FILE_DIRECTORY + '/' + log_file_name)

func _on_SyncManager_sync_stopped() -> void:
	if logging_enabled:
		SyncManager.stop_logging()

func _on_SyncManager_sync_lost() -> void:
	sync_lost_label.visible = true

func _on_SyncManager_sync_regained() -> void:
	sync_lost_label.visible = false

func _on_SyncManager_sync_error(msg: String) -> void:
	message_label.text = "Fatal sync error: " + msg
	sync_lost_label.visible = false
	
	var peer = multiplayer.network_peer
	if peer:
		peer.close_connection()
	SyncManager.clear_peers()

func _on_ResetButton_pressed() -> void:
	SyncManager.stop()
	SyncManager.clear_peers()
	var peer = multiplayer.network_peer
	if peer:
		peer.close_connection()
	get_tree().reload_current_scene()

func setup_match_for_replay(my_peer_id: int, peer_ids: Array, _match_info: Dictionary) -> void:
	var client_peer_id: int
	if my_peer_id == 1:
		client_peer_id = peer_ids[0]
	else:
		client_peer_id = my_peer_id
	$ClientPlayer.set_multiplayer_authority(client_peer_id)

