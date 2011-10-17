shared_examples_for "Koala RestAPI" do
  # REST_CALL
  describe "when making a rest request" do
    it "uses the proper path" do
      method = stub('methodName')
      @api.should_receive(:api).with(
        "method/#{method}",
        anything,
        anything,
        anything
      )

      @api.rest_call(method)
    end

    it "always uses the rest api" do
      @api.should_receive(:api).with(
        anything,
        anything,
        anything,
        hash_including(:rest_api => true)
      )

      @api.rest_call('anything')
    end

    it "sets the read_only option to true if the method is listed in the read-only list" do
      method = Koala::Facebook::RestAPI::READ_ONLY_METHODS.first

      @api.should_receive(:api).with(
        anything,
        anything,
        anything,
        hash_including(:read_only => true)
      )

      @api.rest_call(method)
    end

    it "sets the read_only option to false if the method is not inthe read-only list" do
      method = "I'm not a read-only method"

      @api.should_receive(:api).with(
        anything,
        anything,
        anything,
        hash_including(:read_only => false)
      )

      @api.rest_call(method)
    end


    it "takes an optional hash of arguments" do
      args = {:arg1 => 'arg1'}

      @api.should_receive(:api).with(
        anything,
        hash_including(args),
        anything,
        anything
      )

      @api.rest_call('anything', args)
    end

    it "always asks for JSON" do
      @api.should_receive(:api).with(
        anything,
        hash_including('format' => 'json'),
        anything,
        anything
      )

      @api.rest_call('anything')
    end

    it "passes any options provided to the API" do
      options = {:a => 2}

      @api.should_receive(:api).with(
        anything,
        hash_including('format' => 'json'),
        anything,
        hash_including(options)
      )

      @api.rest_call('anything', {}, options)
    end

    it "uses get by default" do
      @api.should_receive(:api).with(
        anything,
        anything,
        "get",
        anything
      )

      @api.rest_call('anything')
    end

    it "allows you to specify other http methods as the last argument" do
      method = 'bar'
      @api.should_receive(:api).with(
        anything,
        anything,
        method,
        anything
      )

      @api.rest_call('anything', {}, {}, method)
    end

    it "throws an APIError if the result hash has an error key" do
      Koala.stub(:make_request).and_return(Koala::Response.new(500, {"error_code" => "An error occurred!"}, {}))
      lambda { @api.rest_call("koppel", {}) }.should raise_exception(Koala::Facebook::APIError)
    end

    describe "when making a FQL request" do
      it "calls fql.query method" do
        @api.should_receive(:rest_call).with(
          "fql.query", anything, anything
        ).and_return(Koala::Response.new(200, "2", {}))

        @api.fql_query stub('query string')
      end

      it "passes a query argument" do
        query = stub('query string')

        @api.should_receive(:rest_call).with(
          anything, hash_including(:query => query), anything
        )

        @api.fql_query(query)
      end

      it "passes on any other arguments provided" do
        args = {:a => 2}
        @api.should_receive(:rest_call).with(anything, hash_including(args), anything)
        @api.fql_query("a query", args)
      end

      it "passes on any http options provided" do
        opts = {:a => 2}
        @api.should_receive(:rest_call).with(anything, anything, hash_including(opts))
        @api.fql_query("a query", {}, opts)
      end
    end

    describe "when making a FQL-multiquery request" do
      it "calls fql.multiquery method" do
        @api.should_receive(:rest_call).with(
          "fql.multiquery", anything, anything
        ).and_return({})

        @api.fql_multiquery 'query string'
      end

      it "passes a queries argument" do
        queries = stub('query string')
        queries_json = "some JSON"
        MultiJson.stub(:encode).with(queries).and_return(queries_json)

        @api.should_receive(:rest_call).with(
          anything,
          hash_including(:queries => queries_json),
          anything
        )

        @api.fql_multiquery(queries)
      end

      it "simplifies the response format" do
        raw_results = [
          {"name" => "query1", "fql_result_set" => [1, 2, 3]},
          {"name" => "query2", "fql_result_set" => [:a, :b, :c]}
        ]
        expected_results = {
          "query1" => [1, 2, 3],
          "query2" => [:a, :b, :c]
        }

        @api.stub(:rest_call).and_return(raw_results)
        results = @api.fql_multiquery({:query => true})
        results.should == expected_results
      end

      it "passes on any other arguments provided" do
        args = {:a => 2}
        @api.should_receive(:rest_call).with(anything, hash_including(args), anything)
        @api.fql_multiquery("a query", args)
      end

      it "passes on any http options provided" do
        opts = {:a => 2}
        @api.should_receive(:rest_call).with(anything, anything, hash_including(opts))
        @api.fql_multiquery("a query", {}, opts)
      end
    end
  end

  it "can use the beta tier" do
    @api.fql_query("select first_name from user where uid = #{KoalaTest.user2_id}", {}, :beta => true)
  end
end

shared_examples_for "Koala RestAPI with an access token" do
  # FQL
  it "can access public information via FQL" do
    result = @api.fql_query("select first_name from user where uid = #{KoalaTest.user2_id}")
    result.size.should == 1
    result.first['first_name'].should == KoalaTest.user2_name
  end

  it "can access public information via FQL.multiquery" do
    result = @api.fql_multiquery(
      :query1 => "select first_name from user where uid = #{KoalaTest.user2_id}",
      :query2 => "select first_name from user where uid = #{KoalaTest.user1_id}"
    )
    result.size.should == 2
    result["query1"].first['first_name'].should == KoalaTest.user2_name
    result["query2"].first['first_name'].should == KoalaTest.user1_name
  end

  it "can access protected information via FQL" do
    # Tests agains the permissions fql table

    # get the current user's ID
    # we're sneakily using the Graph API, which should be okay since it has its own tests
    g = Koala::Facebook::API.new(@token)
    id = g.get_object("me", :fields => "id")["id"]

    # now send a query about your permissions
    result = @api.fql_query("select read_stream from permissions where uid = #{id}")

    result.size.should == 1
    # we've verified that you have read_stream permissions, so we can test against that
    result.first["read_stream"].should == 1
  end

  it "can access protected information via FQL.multiquery" do
    result = @api.fql_multiquery(
      :query1 => "select post_id from stream where source_id = me()",
      :query2 => "select fromid from comment where post_id in (select post_id from #query1)",
      :query3 => "select uid, name from user where uid in (select fromid from #query2)"
    )
    result.size.should == 3
    result.keys.should include("query1", "query2", "query3")
  end
  
  
  describe "#set_app_properties" do
    it "sends Facebook the properties JSON-encoded as :properties" do
      props = {:a => 2, :c => [1, 2, "d"]}
      @api.should_receive(:rest_call).with(anything, hash_including(:properties => MultiJson.encode(props)), anything, anything)
      @api.set_app_properties(props)
    end

    it "calls the admin.setAppProperties method" do
      @api.should_receive(:rest_call).with("admin.setAppProperties", anything, anything, anything)
      @api.set_app_properties({})
    end

    it "includes any other provided arguments" do
      args = {:c => 3, :d => "a"}
      @api.should_receive(:rest_call).with(anything, hash_including(args), anything, anything)
      @api.set_app_properties({:a => 2}, args)
    end

    it "includes any http_options provided" do
      opts = {:c => 3, :d => "a"}
      @api.should_receive(:rest_call).with(anything, anything, opts, anything)
      @api.set_app_properties({}, {}, opts)
    end
    
    it "makes a POST" do
      @api.should_receive(:rest_call).with(anything, anything, anything, "post")
      @api.set_app_properties({})
    end

    it "can set app properties using the app's access token" do
      oauth = Koala::Facebook::OAuth.new(KoalaTest.app_id, KoalaTest.secret)
      app_token = oauth.get_app_access_token
      @app_api = Koala::Facebook::API.new(app_token)
      @app_api.set_app_properties(:desktop => 0).should be_true
    end
  end
end


shared_examples_for "Koala RestAPI without an access token" do
  # FQL_QUERY
  describe "when making a FQL request" do
    it "can access public information via FQL" do
      result = @api.fql_query("select first_name from user where uid = #{KoalaTest.user2_id}")
      result.size.should == 1
      result.first['first_name'].should == KoalaTest.user2_name
    end

    it "can access public information via FQL.multiquery" do
      result = @api.fql_multiquery(
        :query1 => "select first_name from user where uid = #{KoalaTest.user2_id}",
        :query2 => "select first_name from user where uid = #{KoalaTest.user1_id}"
      )
      result.size.should == 2
      result["query1"].first['first_name'].should == KoalaTest.user2_name
      result["query2"].first['first_name'].should == KoalaTest.user1_name
    end

    it "can't access protected information via FQL" do
      lambda { @api.fql_query("select read_stream from permissions where uid = #{KoalaTest.user2_id}") }.should raise_error(Koala::Facebook::APIError)
    end

    it "can't access protected information via FQL.multiquery" do
      lambda {
        @api.fql_multiquery(
          :query1 => "select post_id from stream where source_id = me()",
          :query2 => "select fromid from comment where post_id in (select post_id from #query1)",
          :query3 => "select uid, name from user where uid in (select fromid from #query2)"
        )
      }.should raise_error(Koala::Facebook::APIError)
    end
  end
  
  it "can't use set_app_properties" do
    lambda { @api.set_app_properties(:desktop => 0) }.should raise_error(Koala::Facebook::APIError)
  end
end
