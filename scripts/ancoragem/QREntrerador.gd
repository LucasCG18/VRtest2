# Código atualizado para gerenciar âncoras QR de forma estável

# Script de ancoragem GS (exemplo)
extends XRAnchor3D

# Função chamada ao detectar um novo QR
func _on_qr_detected(qr_id):
    if not is_anchor_active():
        create_anchor(qr_id)

func create_anchor(qr_id):
    # código para criar a âncora, apenas se não existir
    pass

func update_pose():
    # Código para atualizar a pose com suavização
    pass

# Proteção contra tracking inválido
func _process(delta):
    if tracking_lost():
        handle_lost_tracking()
