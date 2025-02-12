require "test_helper"

module Api
  class OldNodesControllerTest < ActionDispatch::IntegrationTest
    ##
    # test all routes which lead to this controller
    def test_routes
      assert_routing(
        { :path => "/api/0.6/node/1/history", :method => :get },
        { :controller => "api/old_nodes", :action => "index", :node_id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/history.json", :method => :get },
        { :controller => "api/old_nodes", :action => "index", :node_id => "1", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/2", :method => :get },
        { :controller => "api/old_nodes", :action => "show", :node_id => "1", :version => "2" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/2.json", :method => :get },
        { :controller => "api/old_nodes", :action => "show", :node_id => "1", :version => "2", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/2/redact", :method => :post },
        { :controller => "api/old_nodes", :action => "redact", :node_id => "1", :version => "2" }
      )
    end

    def test_index
      node = create(:node, :version => 2)
      create(:old_node, :node_id => node.id, :version => 1, :latitude => 60 * OldNode::SCALE, :longitude => 30 * OldNode::SCALE)
      create(:old_node, :node_id => node.id, :version => 2, :latitude => 61 * OldNode::SCALE, :longitude => 31 * OldNode::SCALE)

      get api_node_versions_path(node)

      assert_response :success
      assert_dom "osm:root", 1 do
        assert_dom "> node", 2 do |dom_nodes|
          assert_dom dom_nodes[0], "> @id", node.id.to_s
          assert_dom dom_nodes[0], "> @version", "1"
          assert_dom dom_nodes[0], "> @lat", "60.0000000"
          assert_dom dom_nodes[0], "> @lon", "30.0000000"

          assert_dom dom_nodes[1], "> @id", node.id.to_s
          assert_dom dom_nodes[1], "> @version", "2"
          assert_dom dom_nodes[1], "> @lat", "61.0000000"
          assert_dom dom_nodes[1], "> @lon", "31.0000000"
        end
      end
    end

    ##
    # test that redacted nodes aren't visible in the history
    def test_index_redacted
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      get api_node_versions_path(node)
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 0,
                    "redacted node #{node_v1.node_id} version #{node_v1.version} shouldn't be present in the history."

      # not even to a logged-in user
      auth_header = bearer_authorization_header
      get api_node_versions_path(node), :headers => auth_header
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 0,
                    "redacted node #{node_v1.node_id} version #{node_v1.version} shouldn't be present in the history, even when logged in."
    end

    def test_show
      node = create(:node, :version => 2)
      create(:old_node, :node_id => node.id, :version => 1, :latitude => 60 * OldNode::SCALE, :longitude => 30 * OldNode::SCALE)
      create(:old_node, :node_id => node.id, :version => 2, :latitude => 61 * OldNode::SCALE, :longitude => 31 * OldNode::SCALE)

      get api_node_version_path(node, 1)

      assert_response :success
      assert_dom "osm:root", 1 do
        assert_dom "> node", 1 do
          assert_dom "> @id", node.id.to_s
          assert_dom "> @version", "1"
          assert_dom "> @lat", "60.0000000"
          assert_dom "> @lon", "30.0000000"
        end
      end

      get api_node_version_path(node, 2)

      assert_response :success
      assert_dom "osm:root", 1 do
        assert_dom "> node", 1 do
          assert_dom "> @id", node.id.to_s
          assert_dom "> @version", "2"
          assert_dom "> @lat", "61.0000000"
          assert_dom "> @lon", "31.0000000"
        end
      end
    end

    def test_show_not_found
      check_not_found_id_version(70000, 312344)
      check_not_found_id_version(-1, -13)
      check_not_found_id_version(create(:node).id, 24354)
      check_not_found_id_version(24356, create(:node).version)
    end

    ##
    # test that redacted nodes aren't visible, regardless of
    # authorisation except as moderator...
    def test_show_redacted
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      get api_node_version_path(node_v1.node_id, node_v1.version)
      assert_response :forbidden, "Redacted node shouldn't be visible via the version API."

      # not even to a logged-in user
      auth_header = bearer_authorization_header
      get api_node_version_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :forbidden, "Redacted node shouldn't be visible via the version API, even when logged in."
    end

    # Ensure the lat/lon is formatted as a decimal e.g. not 4.0e-05
    def test_lat_lon_xml_format
      old_node = create(:old_node, :latitude => (0.00004 * OldNode::SCALE).to_i, :longitude => (0.00008 * OldNode::SCALE).to_i)

      get api_node_versions_path(old_node.node_id)
      assert_match(/lat="0.0000400"/, response.body)
      assert_match(/lon="0.0000800"/, response.body)
    end

    ##
    # test the redaction of an old version of a node, while not being
    # authorised.
    def test_redact_node_unauthorised
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)

      do_redact_node(node_v3,
                     create(:redaction))
      assert_response :unauthorized, "should need to be authenticated to redact."
    end

    ##
    # test the redaction of an old version of a node, while being
    # authorised as a normal user.
    def test_redact_node_normal_user
      auth_header = bearer_authorization_header

      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)

      do_redact_node(node_v3,
                     create(:redaction),
                     auth_header)
      assert_response :forbidden, "should need to be moderator to redact."
    end

    ##
    # test that, even as moderator, the current version of a node
    # can't be redacted.
    def test_redact_node_current_version
      auth_header = bearer_authorization_header create(:moderator_user)

      node = create(:node, :with_history, :version => 4)
      node_v4 = node.old_nodes.find_by(:version => 4)

      do_redact_node(node_v4,
                     create(:redaction),
                     auth_header)
      assert_response :bad_request, "shouldn't be OK to redact current version as moderator."
    end

    def test_redact_node_by_regular_without_write_redactions_scope
      auth_header = bearer_authorization_header(create(:user), :scopes => %w[read_prefs write_api])
      do_redact_redactable_node(auth_header)
      assert_response :forbidden, "should need to be moderator to redact."
    end

    def test_redact_node_by_regular_with_write_redactions_scope
      auth_header = bearer_authorization_header(create(:user), :scopes => %w[write_redactions])
      do_redact_redactable_node(auth_header)
      assert_response :forbidden, "should need to be moderator to redact."
    end

    def test_redact_node_by_moderator_without_write_redactions_scope
      auth_header = bearer_authorization_header(create(:moderator_user), :scopes => %w[read_prefs write_api])
      do_redact_redactable_node(auth_header)
      assert_response :forbidden, "should need to have write_redactions scope to redact."
    end

    def test_redact_node_by_moderator_with_write_redactions_scope
      auth_header = bearer_authorization_header(create(:moderator_user), :scopes => %w[write_redactions])
      do_redact_redactable_node(auth_header)
      assert_response :success, "should be OK to redact old version as moderator with write_redactions scope."
    end

    ##
    # test the redaction of an old version of a node, while being
    # authorised as a moderator.
    def test_redact_node_moderator
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)
      auth_header = bearer_authorization_header create(:moderator_user)

      do_redact_node(node_v3, create(:redaction), auth_header)
      assert_response :success, "should be OK to redact old version as moderator."

      # check moderator can still see the redacted data, when passing
      # the appropriate flag
      get api_node_version_path(node_v3.node_id, node_v3.version), :headers => auth_header
      assert_response :forbidden, "After redaction, node should be gone for moderator, when flag not passed."
      get api_node_version_path(node_v3.node_id, node_v3.version, :show_redactions => "true"), :headers => auth_header
      assert_response :success, "After redaction, node should not be gone for moderator, when flag passed."

      # and when accessed via history
      get api_node_versions_path(node)
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v3.node_id}'][version='#{node_v3.version}']", 0,
                    "node #{node_v3.node_id} version #{node_v3.version} should not be present in the history for moderators when not passing flag."
      get api_node_versions_path(node, :show_redactions => "true"), :headers => auth_header
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v3.node_id}'][version='#{node_v3.version}']", 1,
                    "node #{node_v3.node_id} version #{node_v3.version} should still be present in the history for moderators when passing flag."
    end

    # testing that if the moderator drops auth, he can't see the
    # redacted stuff any more.
    def test_redact_node_is_redacted
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)
      auth_header = bearer_authorization_header create(:moderator_user)

      do_redact_node(node_v3, create(:redaction), auth_header)
      assert_response :success, "should be OK to redact old version as moderator."

      # re-auth as non-moderator
      auth_header = bearer_authorization_header

      # check can't see the redacted data
      get api_node_version_path(node_v3.node_id, node_v3.version), :headers => auth_header
      assert_response :forbidden, "Redacted node shouldn't be visible via the version API."

      # and when accessed via history
      get api_node_versions_path(node), :headers => auth_header
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v3.node_id}'][version='#{node_v3.version}']", 0,
                    "redacted node #{node_v3.node_id} version #{node_v3.version} shouldn't be present in the history."
    end

    ##
    # test the unredaction of an old version of a node, while not being
    # authorised.
    def test_unredact_node_unauthorised
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      post node_version_redact_path(node_v1.node_id, node_v1.version)
      assert_response :unauthorized, "should need to be authenticated to unredact."
    end

    ##
    # test the unredaction of an old version of a node, while being
    # authorised as a normal user.
    def test_unredact_node_normal_user
      user = create(:user)
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      auth_header = bearer_authorization_header user

      post node_version_redact_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :forbidden, "should need to be moderator to unredact."
    end

    ##
    # test the unredaction of an old version of a node, while being
    # authorised as a moderator.
    def test_unredact_node_moderator
      moderator_user = create(:moderator_user)
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      auth_header = bearer_authorization_header moderator_user

      post node_version_redact_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :success, "should be OK to unredact old version as moderator."

      # check moderator can now see the redacted data, when not
      # passing the aspecial flag
      get api_node_version_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :success, "After unredaction, node should not be gone for moderator."

      # and when accessed via history
      get api_node_versions_path(node)
      assert_response :success, "Unredaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 1,
                    "node #{node_v1.node_id} version #{node_v1.version} should now be present in the history for moderators without passing flag."

      auth_header = bearer_authorization_header

      # check normal user can now see the redacted data
      get api_node_version_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :success, "After unredaction, node should be visible to normal users."

      # and when accessed via history
      get api_node_versions_path(node)
      assert_response :success, "Unredaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 1,
                    "node #{node_v1.node_id} version #{node_v1.version} should now be present in the history for normal users without passing flag."
    end

    private

    def do_redact_redactable_node(headers = {})
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)
      do_redact_node(node_v3, create(:redaction), headers)
    end

    def do_redact_node(node, redaction, headers = {})
      get api_node_version_path(node.node_id, node.version), :headers => headers
      assert_response :success, "should be able to get version #{node.version} of node #{node.node_id}."

      # now redact it
      post node_version_redact_path(node.node_id, node.version), :params => { :redaction => redaction.id }, :headers => headers
    end

    def check_not_found_id_version(id, version)
      get api_node_version_path(id, version)
      assert_response :not_found
    rescue ActionController::UrlGenerationError => e
      assert_match(/No route matches/, e.to_s)
    end
  end
end
