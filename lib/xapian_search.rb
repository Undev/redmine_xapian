require 'xapian'

module XapianSearch  
  def XapianSearch.search_attachments(tokens, limit_options, offset, projects_to_search, all_words, user_stem_lang, user_stem_strategy )
    xpattachments = Array.new
    return [xpattachments,0] unless Setting.plugin_redmine_xapian['enable'] == "true"
    Rails.logger.debug "DEBUG: global settings dump" + Setting.plugin_redmine_xapian.inspect
    Rails.logger.debug "DEBUG: user_stem_lang: " + user_stem_lang.inspect
    Rails.logger.debug "DEBUG: user_stem_strategy: " + user_stem_strategy.inspect
    Rails.logger.debug "DEBUG: databasepath: " + get_database_path(user_stem_lang)
    databasepath = get_database_path(user_stem_lang)

    database = Xapian::Database.new(databasepath)

    # Start an enquire session.
    
    enquire = Xapian::Enquire.new(database)

    # Combine the rest of the command line arguments with spaces between
    # them, so that simple queries don't have to be quoted at the shell
    # level.
    #queryString = ARGV[1..-1].join(' ')
    queryString = tokens.join(' ')
    # Parse the query string to produce a Xapian::Query object.
    qp = Xapian::QueryParser.new()
    stemmer = Xapian::Stem.new(user_stem_lang)
    qp.stemmer = stemmer
    qp.database = database
    case @user_stem_strategy
      when "STEM_NONE" then qp.stemming_strategy = Xapian::QueryParser::STEM_NONE
      when "STEM_SOME" then qp.stemming_strategy = Xapian::QueryParser::STEM_SOME
      when "STEM_ALL" then qp.stemming_strategy = Xapian::QueryParser::STEM_ALL
    end
    if all_words
      qp.default_op = Xapian::Query::OP_AND
    else  
      qp.default_op = Xapian::Query::OP_OR
    end
    query = qp.parse_query(queryString)
    Rails.logger.debug "DEBUG queryString is: #{queryString}"
    Rails.logger.debug "DEBUG: Parsed query is: #{query.description()} "

    # Find the top 100 results for the query.
    enquire.query = query
    matchset = enquire.mset(0, 1000)
  
    return [xpattachments,0] if matchset.nil?

    # Display the results.
    #logger.debug "#{@matchset.matches_estimated()} results found."
    Rails.logger.debug "DEBUG: Matches 1-#{matchset.size}:\n"

    matchset.matches.each do |m|
      #Rails.logger.debug "#{m.rank + 1}: #{m.percent}% docid=#{m.docid} [#{m.document.data}]\n"
      #logger.debug "DEBUG: m: " + m.document.data.inspect
      docdata=m.document.data{url}
      dochash=Hash[*docdata.scan(/(url|sample|modtime|type|size)=\/?([^\n\]]+)/).flatten]
      if not dochash.nil? then
        find_conditions = Attachment.merge_conditions(limit_options[:conditions], :disk_filename => dochash.fetch('url'))
        docattach = Attachment.find(:first, :conditions =>  find_conditions)
        if not docattach.nil?
          container_type = docattach["container_type"]
          if container_type == "Article" and not Redmine::Search.available_search_types.include?("articles")
            Rails.logger.debug "DEBUG: Knowledgebase plugin in not installed.."
          elsif docattach.container
            Rails.logger.debug "DEBUG: adding attach.. "

            user = User.current
            project = docattach.container.project
            container_permission = SearchStrategies::ContainerTypeHelper.to_permission(container_type)
            can_view_container = user.allowed_to?(container_permission, project)
            
            allowed = case container_type
            when "Article"
              true
            when "Issue"
              can_view_issue = Issue.find_by_id(docattach[:container_id]).visible?
              allowed = can_view_container && can_view_issue
            else
              allowed = can_view_container
            end

            if allowed && project_included(docattach.container.project.id, projects_to_search)
              docattach[:description] = dochash["sample"]
              xpattachments.push ( docattach )
            else
              Rails.logger.debug "DEBUG: user without permissions"
            end
          end
        end
      end
    end

    numattach = xpattachments.size
    xpattachments = xpattachments.sort_by{|x| x[:created_on] }
    
    if RUBY_VERSION >= "1.9"
      xpattachments.each do |attachment|
        attachment[:description].force_encoding('UTF-8')
      end
    end

    [xpattachments, numattach]
  end

  def XapianSearch.project_included(project_id, projects_to_search)
    return true if projects_to_search.nil?
    projects_to_search.any? { |p| p[:id] == project_id }
  end

  def XapianSearch.get_database_path(user_stem_lang)
    db = Setting.plugin_redmine_xapian['index_database'].strip
    lang = user_stem_lang

    File.join(db, lang)
  end
end
