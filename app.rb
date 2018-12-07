# coding: utf-8
require 'pry-byebug'
require 'linkeddata'
require 'fileutils'
require 'pathname'

class TemplatesTTLSplitter

  DC = RDF::Vocab::DC
  MU = RDF::Vocabulary.new("http://mu.semte.ch/vocabularies/core/")
  EXT = RDF::Vocabulary.new("http://mu.semte.ch/vocabularies/ext/")


  # From a big TTL file coming from backend, make small files
  def split_initial_TTL(file_path, output_folder)

    #TODO
    #     queryable = RDF::Repository.load("etc/doap.ttl")
    # sse = SPARQL.parse("SELECT * WHERE { ?s ?p ?o }")
    # sse.execute(queryable) do |result|
    #   result.inspect
    # end
    #
    #%("dit" is een string)
    #
    query = RDF::Query.new({
                             template: {
                               RDF.type => EXT["Template"],
                               :p => :o
                             }
                           })
    templates = get_templates(load_TTL(file_path), query)
    templates.each do |template_uri, properties|
      graph = template_hash_to_graph(template_uri, properties)
      write_ttl_to_file(output_folder, replace_non_ascii(properties["http://purl.org/dc/terms/title"].tr(" ", "-")), graph)
    end
  end

  def write_migration_ttl(folder, ttl_file_path)
    file_name = File.basename(ttl_file_path , File.extname(ttl_file_path))
    file_path = File.join(folder, DateTime.now.strftime("%Y%m%d%H%M%S") +  "-" + file_name + ".ttl")
    FileUtils.cp(ttl_file_path, file_path)
  end

  def write_sparql(folder, query)
    file_path = File.join(folder, DateTime.now.strftime("%Y%m%d%H%M%S") +  "-" + 'move-templates'  + ".sparql")
    open(file_path, 'w') { |f| f << query }
  end

  def migrate_to_from_app_to_public()
    query = %(
                    DELETE {
                      GRAPH <http://mu.semte.ch/application> {
                        ?s ?p ?o .
                      }
                    }
                    INSERT {
                      GRAPH <http://mu.semte.ch/graphs/public> {
                        ?s ?p ?o .
                      }
                    }
                    WHERE {
                      GRAPH <http://mu.semte.ch/application> {
                        ?s a <http://mu.semte.ch/vocabularies/ext/Template> .
                        ?s ?p ?o .
                      }
                    };
     )
  end

  def create_flush_query(ttl_files)
    uris_to_flush = []
    ttl_files.each do |ttl_file|
      queryable = RDF::Repository.load(ttl_file)
      sse = SPARQL.parse("SELECT * WHERE { ?s a <#{EXT["Template"]}> }")
      sse.execute(queryable) do |result|
        uris_to_flush << result.s.value
      end
    end

    uris_to_flush = uris_to_flush.map{ |u| "<#{u}>"}.join(",")

    query = %(
               PREFIX ns5:  <http://purl.org/dc/terms/>
               PREFIX ns2: <http://mu.semte.ch/vocabularies/core/>
               # delete subscenario
                DELETE {
                  GRAPH ?g {
                    ?s ?p ?o.
                  }
                }

                WHERE {
                  GRAPH ?g {
                    ?s ?p ?o .
                    FILTER( ?s IN (#{uris_to_flush})) .
                  }
                };
           )
    query
  end

  def replace_non_ascii(str)
    encoding_options = {
      :invalid           => :replace,  # Replace invalid byte sequences
      :undef             => :replace,  # Replace anything not defined in ASCII
      :replace           => '',        # Use a blank for those replacements
      :universal_newline => true,       # Always break lines with \n
    }
    ascii = str.encode(Encoding.find('ASCII'), encoding_options)
    ascii
  end

  def update_migrations(templates_git_folder, output_folder, start_commit, end_commit)
    all_files = get_changed_files(templates_git_folder, start_commit, end_commit)

    check_for_valid_files(all_files)
    # only pick up ttl files
    all_files = all_files.select{ |f| File.file?(f) }.select{ |f|  File.extname(f) == '.ttl'}
    flush_query = create_flush_query(all_files)
    move_query = migrate_to_from_app_to_public()

    # write files (in a very stupid way)
    write_sparql(output_folder, flush_query)
    sleep(1)
    all_files.each do |f|
      write_migration_ttl(output_folder, f)
      sleep(1)
      p "Writing slowly (this is silly)"
    end
    sleep(1)
    write_sparql(output_folder, move_query)
    p "Finished creating migration, please validate the content manually. So many possible cases not supported!"
  end

  def check_for_valid_files(files)
    files.each do |f|
      if(!File.file?(f))
        p "---------------- Warning #{f} does not exist."
        p "Probably related to removed file. The script does not handle this case"
        p "You will have to manually create migration...."
      end
    end
    files.each do |f|
      if(!File.extname(f) == '.ttl')
        p "---------------- Warning #{f} is not a .ttl file. Skipping"
      end
    end
  end

  def get_changed_files(folder, start_commit, end_commit)
    current_dir = Dir.pwd
    command = "git log --name-only --pretty=oneline --full-index #{start_commit}..#{end_commit} | grep -vE '^[0-9a-f]{40} ' | sort | uniq"
    begin
      Dir.chdir folder
      output = `#{command}`
      paths = output.split(/\n/)
      paths = paths.map{ |p| File.expand_path(p) }
    ensure
      Dir.chdir current_dir
    end
    paths
  end

  #TODO: this is brittle
  def template_hash_to_graph(uri, properties)
    graph = RDF::Graph.new
    subject = RDF::URI(uri)

    graph << RDF.Statement(subject, RDF.type, EXT["Template"])
    properties.each do |p, o|
      graph << RDF.Statement(subject, RDF::URI(p), o)
    end
    graph
  end

  def load_TTL(file_path)
    RDF::Graph.load(file_path, format:  :ttl)
  end

  def get_templates(graph, query)
    templates = {}
    query.execute(graph).each do |solution|
      if(!templates[solution.template.value])
        templates[solution.template.value] = {}
      end
      templates[solution.template.value].merge!({ solution.p.value => solution.o.value })
    end
    templates
  end

  def write_ttl_to_file(folder, file, graph, timestamp_ttl = false)
    file_path = File.join(folder, file + '.ttl')
    if timestamp_ttl
      file_path = File.join(folder, DateTime.now.strftime("%Y%m%d%H%M%S") +  "-" + file  + ".ttl")
    end
    RDF::Writer.open(file_path) { |writer| writer << graph }
  end

end

serializer = TemplatesTTLSplitter.new()
#serializer.split_initial_TTL("input/orig-templates.ttl", "output/initial")
#serializer.update_migrations('/home/felix/git/rpio/lblod/editor-templates', 'output/test', 'HEAD', 'HEAD^')
serializer.update_migrations('/repo', 'output', ARGV[0], ARGV[1])
