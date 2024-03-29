# Import API specifics
use 'ontap_base'

resource_name :ontap_ethernet_port
provides :ontap_ethernet_port, target_mode: true, platform: 'ontap'

description 'Changes a port, creates a new VLAN (such as node1:e0a-100) or creates LAG (ifgrp, such as node2:a0a).'

property :name, String,
          name_property: true,
          description: <<~DOC
            Portname, such as e0a, e1b-100 (VLAN on ethernet), a0c (LAG/ifgrp), a0d-200 (vlan on LAG/ifgrp).
          DOC

property :node_name, String,
          required: true,
          description: 'Node of the port.'

property :broadcast_domain, String,
          description: 'Name of the broadcast domain, scoped to its IPspace'

property :ipspace, String,
          description: 'Name of the broadcast domain’s IPspace'

rest_api_collection '/api/network/ethernet/ports'
rest_api_document   '/api/network/ethernet/ports?name={name}&node.name={node}&fields=*', first_element_only: true

rest_property_map({
                    name: 'name',
                    node_name: 'node.name',

                    broadcast_domain: 'broadcast_domain.name',
                    ipspace: 'broadcast_domain.ipspace'
                  })

action :enable, description: 'Enable a port.' do
  if current_resource
    enable_port unless port_enabled?
  else
    logger.debug format('ONTAP port %<port_name>s on node %<node_name>s does not exist. Skipping.',
                        node_name: new_resource.name,
                        port_name: new_resource.node)
  end
end

action :disable, description: 'Disable a port.' do
  if current_resource
    disable_port unless port_disabled?
  else
    logger.debug format('ONTAP port %<port_name>s on node %<node_name>s does not exist. Skipping.',
                        port_name: new_resource.name,
                        node_name: new_resource.node)
  end
end

action_class do
  def port_state
    rest_get.fetch('enabled')
  end

  def port_enabled?
    port_state
  end

  def port_disabled?
    !port_state
  end

  def enable_port
    rest_patch({ 'enabled' => true })
  end

  def disable_port
    rest_patch({ 'disabled' => true })
  end
end
