# frozen_string_literal: true

#
# Author:: Justin Steele (<justin.steele@oracle.com>)
#
# Copyright (C) 2024, Stephen Pearson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen/driver/oci'
require 'kitchen/provisioner/dummy'
require 'kitchen/transport/dummy'
require 'kitchen/verifier/dummy'
require 'spec_helper'

describe Kitchen::Driver::Oci do
  describe '#create' do
    context 'compute' do
      include_context 'compute'
      let(:state) { {} }

      context 'standard compute' do
        let(:driver_config) do
          {
            compartment_id: compartment_ocid,
            availability_domain: availability_domain,
            subnet_id: subnet_ocid,
            shape: shape,
            image_id: image_ocid
          }
        end

        it 'creates a compute instance with no volumes' do
          expect(compute_client).to receive(:launch_instance).with(launch_instance_request)
          expect(compute_client).to receive(:get_instance).with(instance_ocid)
          expect(compute_client).to receive(:list_vnic_attachments).with(compartment_ocid, instance_id: instance_ocid)
          expect(transport).to receive_message_chain('connection.wait_until_ready')
          driver.create(state)
          expect(state).to match(
            {
              hostname: private_ip,
              server_id: instance_ocid,
              volume_attachments: [],
              volumes: []
            }
          )
        end
      end

      context 'standard compute with nsg' do
        let(:driver_config) do
          {
            compartment_id: compartment_ocid,
            availability_domain: availability_domain,
            subnet_id: subnet_ocid,
            shape: shape,
            image_id: image_ocid,
            nsg_ids: [
              'ocid1.networksecuritygroup.oc1.fake.aaaaaaaaaabcdefghijklmnopqrstuvwxyz12345',
              'ocid1.networksecuritygroup.oc1.fake.aaaaaaaaaabcdefghijklmnopqrstuvwxyz67890'
            ]
          }
        end

        it 'creates a compute instance with nsg_ids specified' do
          expect(compute_client).to receive(:launch_instance).with(launch_instance_request)
          driver.create(state)
          expect(state).to match(
            {
              hostname: private_ip,
              server_id: instance_ocid,
              volume_attachments: [],
              volumes: []
            }
          )
        end
      end

      context 'compute with volumes' do
        context 'iscsi volume' do
          let(:driver_config) do
            {
              compartment_id: compartment_ocid,
              availability_domain: availability_domain,
              subnet_id: subnet_ocid,
              shape: shape,
              image_id: image_ocid,
              volumes: [
                {
                  name: iscsi_display_name,
                  size_in_gbs: 10,
                  type: 'iscsi'
                }
              ]
            }
          end

          it 'creates a compute instance with iscsi attached volume' do
            expect(blockstorage_client).to receive(:create_volume).with(iscsi_volume_details).and_return(iscsi_blockstorage_resp)
            expect(blockstorage_client).to receive(:get_volume).with(iscsi_volume_ocid).and_return(iscsi_blockstorage_resp)
            expect(compute_client).to receive(:attach_volume).with(iscsi_attachment).and_return(iscsi_attachment_resp)
            expect(compute_client).to receive(:get_volume_attachment).with(attachment_ocid).and_return(iscsi_attachment_resp)
            expect(iscsi_blockstorage_resp).to receive(:wait_until).with(:lifecycle_state,
                                                                         Lifecycle.volume('available')).and_return(iscsi_blockstorage_resp)
            expect(iscsi_attachment_resp).to receive(:wait_until).with(:lifecycle_state,
                                                                       Lifecycle.volume_attachment('attached')).and_return(iscsi_attachment_resp)
            driver.create(state)
            expect(state).to match(
              {
                hostname: private_ip,
                server_id: instance_ocid,
                volume_attachments: [
                  {
                    id: attachment_ocid,
                    iqn: iqn,
                    iqn_ipv4: ipv4,
                    port: port
                  }
                ],
                volumes: [
                  {
                    attachment_type: driver_config[:volumes][0][:type],
                    display_name: driver_config[:volumes][0][:name],
                    id: iscsi_volume_ocid
                  }
                ]
              }
            )
          end
        end

        context 'paravirtual volume' do
          let(:driver_config) do
            {
              compartment_id: compartment_ocid,
              availability_domain: availability_domain,
              subnet_id: subnet_ocid,
              shape: shape,
              image_id: image_ocid,
              volumes: [
                {
                  name: pv_display_name,
                  size_in_gbs: 10
                }
              ]
            }
          end

          it 'creates a compute instance with paravirtual attached volume by default' do
            expect(blockstorage_client).to receive(:create_volume).with(pv_volume_details).and_return(pv_blockstorage_resp)
            expect(blockstorage_client).to receive(:get_volume).with(pv_volume_ocid).and_return(pv_blockstorage_resp)
            expect(compute_client).to receive(:attach_volume).with(pv_attachment).and_return(pv_attachment_resp)
            expect(compute_client).to receive(:get_volume_attachment).with(attachment_ocid).and_return(pv_attachment_resp)
            expect(pv_blockstorage_resp).to receive(:wait_until).with(:lifecycle_state,
                                                                      Lifecycle.volume('available')).and_return(pv_blockstorage_resp)
            expect(pv_attachment_resp).to receive(:wait_until).with(:lifecycle_state,
                                                                    Lifecycle.volume_attachment('attached')).and_return(pv_attachment_resp)
            driver.create(state)
            expect(state).to match(
              {
                hostname: private_ip,
                server_id: instance_ocid,
                volume_attachments: [
                  {
                    id: attachment_ocid
                  }
                ],
                volumes: [
                  {
                    attachment_type: 'paravirtual',
                    display_name: pv_display_name,
                    id: pv_volume_ocid
                  }
                ]
              }
            )
          end
        end
      end
    end

    context 'dbaas' do
      include_context 'dbaas'
      let(:state) { {} }
      it 'creates a dbaas instance' do
        expect(dbaas_client).to receive(:launch_db_system).with(db_system_launch_details)
        expect(dbaas_client).to receive(:get_db_system).with(db_system_ocid).and_return(dbaas_resp)
        expect(dbaas_client).to receive(:list_db_nodes).with(compartment_ocid, db_system_id: db_system_ocid).and_return(db_nodes_resp)
        expect(dbaas_resp).to receive(:wait_until).with(:lifecycle_state, Lifecycle.dbaas, max_interval_seconds: 900, max_wait_seconds: 21600)
        expect(transport).to receive_message_chain('connection.wait_until_ready')
        driver.create(state)
        expect(state).to match(
          {
            hostname: private_ip,
            server_id: db_system_ocid,
            volume_attachments: [],
            volumes: []
          }
        )
      end
    end
  end

  describe '#destroy' do
    context 'compute' do
      include_context 'compute'
      let(:driver_config) do
        {
          compartment_id: compartment_ocid,
          availability_domain: availability_domain,
          subnet_id: subnet_ocid,
          shape: shape
        }
      end

      context 'standard compute' do
        let(:state) { { server_id: instance_ocid } }

        it 'destroys a compute instance with no volumes' do
          expect(compute_client).to receive(:terminate_instance).with(instance_ocid)
          expect(transport).to receive_message_chain('connection.close')
          driver.destroy(state)
        end
      end

      context 'compute with volumes' do
        let(:state) do
          {
            server_id: instance_ocid,
            volumes: [
              {
                id: pv_volume_ocid,
                display_name: pv_display_name
              }
            ],
            volume_attachments: [
              {
                id: attachment_ocid
              }
            ]
          }
        end
        it 'destroys a compute instance with volumes attached' do
          expect(compute_client).to receive(:detach_volume).with(attachment_ocid)
          expect(blockstorage_client).to receive(:delete_volume).with(pv_volume_ocid)
          driver.destroy(state)
        end
      end
    end

    context 'dbaas' do
      include_context 'dbaas'
      let(:state) { { server_id: db_system_ocid } }

      it 'destroys a dbaas instance' do
        expect(dbaas_client).to receive(:terminate_db_system).with(db_system_ocid)
        expect(transport).to receive_message_chain('connection.close')
        driver.destroy(state)
      end
    end
  end
end