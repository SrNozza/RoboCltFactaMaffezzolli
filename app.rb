#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'sinatra'
require 'httparty'
require 'json'
require 'base64'
require 'csv'
require 'date'

# Configurações da aplicação
configure do
  set :bind, '0.0.0.0'
  set :port, ENV['PORT'] || 4570  # Railway usa PORT environment variable
  set :public_folder, 'public'
  set :views, 'views'
end

# Configurações da API Facta
API_BASE = 'https://webservice.facta.com.br'
CREDENTIALS = {
  login: '96676',
  password: 'feaeqoxmbh3lzzpg3wpb',
  usuario_certificado: '96676_bombom'
}

# Cache do token
$token_cache = { token: nil, expires: nil }

# Função para gerar token
def get_token
  begin
    # Verifica se tem token válido em cache
    if $token_cache[:token] && $token_cache[:expires] && Time.now < $token_cache[:expires]
      puts "✅ Usando token em cache"
      return $token_cache[:token]
    end
    
    # Gera novo token
    auth_string = "#{CREDENTIALS[:login]}:#{CREDENTIALS[:password]}"
    encoded_auth = Base64.strict_encode64(auth_string)
    
    headers = {
      'Authorization' => "Basic #{encoded_auth}",
      'Content-Type' => 'application/json',
      'User-Agent' => 'RoboMaffezzolli/1.0'
    }
    
    puts "🔑 Solicitando token da API Facta..."
    puts "🔑 URL: #{API_BASE}/gera-token"
    puts "🔑 Headers: #{headers}"
    
    response = HTTParty.get("#{API_BASE}/gera-token", 
      headers: headers,
      timeout: 30
    )
    
    puts "🔑 Status: #{response.code}"
    puts "🔑 Resposta: #{response.body}"
    
    if response.success?
      data = JSON.parse(response.body)
      
      if data['erro'] == false && data['token']
        $token_cache[:token] = data['token']
        $token_cache[:expires] = Time.now + (50 * 60) # 50 minutos
        
        puts "✅ Token gerado com sucesso!"
        return data['token']
      else
        puts "❌ API retornou erro: #{data['mensagem']}"
        return nil
      end
    else
      puts "❌ Erro HTTP: #{response.code} - #{response.message}"
      return nil
    end
    
  rescue => e
    puts "❌ Erro ao gerar token: #{e.message}"
    puts e.backtrace
    return nil
  end
end

# Função para consultar simulação de valores (Etapa 5)
def consultar_simulacao(cpf, data_nascimento, codigo_tabela, prazo, valor_parcela)
  begin
    token = get_token
    return nil unless token
    
    headers = {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/x-www-form-urlencoded'
    }
    
    body = {
      'produto' => 'D',
      'tipo_operacao' => '13',
      'averbador' => '10010',
      'convenio' => '3',
      'cpf' => cpf,
      'data_nascimento' => data_nascimento,
      'login_certificado' => '96676',
      'codigo_tabela' => codigo_tabela,
      'prazo' => prazo,
      'valor_operacao' => '1000.00',  # Valor inicial
      'valor_parcela' => valor_parcela,
      'coeficiente' => '0.029000'
    }
    
    url = "#{API_BASE}/proposta/etapa1-simulador"
    puts "🔍 Consultando simulação: CPF #{cpf}, Tabela #{codigo_tabela}, Prazo #{prazo}, Parcela #{valor_parcela}"
    
    response = HTTParty.post(url, 
      headers: headers,
      body: body,
      timeout: 30
    )
    
    puts "🔍 Status simulação: #{response.code}"
    puts "🔍 Resposta simulação: #{response.body}"
    
    if response.success?
      data = JSON.parse(response.body)
      if data['erro'] == false
        return {
          id_simulador: data['id_simulador'],
          valor_maximo_calculado: (valor_parcela.to_f * prazo.to_i).round(2)
        }
      end
    end
    
    return nil
    
  rescue => e
    puts "❌ Erro na simulação: #{e.message}"
    return nil
  end
end

# Função para consultar CPF
def consultar_cpf(cpf)
  begin
    token = get_token
    return { erro: true, mensagem: 'Token não obtido' } unless token
    
    headers = {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json',
      'User-Agent' => 'RoboMaffezzolli/1.0'
    }
    
    url = "#{API_BASE}/consignado-trabalhador/autoriza-consulta?cpf=#{cpf}"
    puts "🔍 Consultando CPF #{cpf}: #{url}"
    
    response = HTTParty.get(url, 
      headers: headers,
      timeout: 30
    )
    
    puts "🔍 Status: #{response.code}"
    puts "🔍 Resposta: #{response.body}"
    
    if response.success?
      data = JSON.parse(response.body)
      
      if data['erro'] == false && data['dados_trabalhador'] && data['dados_trabalhador']['dados'] && data['dados_trabalhador']['dados'].length > 0
        # Extrai dados do primeiro trabalhador
        trabalhador = data['dados_trabalhador']['dados'][0]
        puts "✅ Dados extraídos: #{trabalhador['nome']}, Renda: #{trabalhador['valorTotalVencimentos']}"
        return {
          cpf: cpf,
          erro: false,
          mensagem: data['mensagem'],
          raw_data: trabalhador
        }
      else
        puts "❌ Erro na resposta: #{data['mensagem']}"
        return {
          cpf: cpf,
          erro: true,
          mensagem: data['mensagem'] || 'Dados não encontrados',
          raw_data: nil
        }
      end
    else
      return {
        cpf: cpf,
        erro: true,
        mensagem: "Erro HTTP: #{response.code}",
        raw_data: nil
      }
    end
    
  rescue => e
    puts "❌ Erro ao consultar CPF #{cpf}: #{e.message}"
    return {
      cpf: cpf,
      erro: true,
      mensagem: "Exceção: #{e.message}",
      raw_data: nil
    }
  end
end

# Função para consultar política de crédito
def consultar_politica_credito(cpf, data_nascimento, tempo_empresa, valor_renda, sexo)
  begin
    token = get_token
    return nil unless token
    
    # Calcula CNAE padrão (00) e prazo padrão (36)
    cnae = "00"
    prazo = 36
    valor = (valor_renda.to_f * 100).to_i  # Converte para centavos
    
    url = "#{API_BASE}/consignado-trabalhador/valida-politica-credito"
    params = {
      cpf: cpf,
      tempo_meses_empresa: tempo_empresa,
      data_nascimento: data_nascimento,
      prazo: prazo,
      valor: valor,
      cnae: cnae,
      sexo: sexo
    }
    
    headers = {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json',
      'User-Agent' => 'RoboMaffezzolli/1.0'
    }
    
    puts "🔍 Consultando política de crédito para CPF #{cpf}..."
    puts "🔍 URL: #{url}"
    puts "🔍 Params: #{params}"
    
    response = HTTParty.get(url, query: params, headers: headers, timeout: 30)
    
    puts "📊 Status política de crédito: #{response.code}"
    puts "📊 Response política de crédito: #{response.body}"
    
    if response.success?
      data = JSON.parse(response.body)
      if data['erro'] == false
        return {
          prazo_maximo: data['prazo'],
          valor_maximo: data['valor']
        }
      end
    end
    
    return nil
  rescue => e
    puts "❌ Erro na consulta de política de crédito: #{e.message}"
    return nil
  end
end

# Função para consultar operações disponíveis
def consultar_operacoes_disponiveis(cpf, data_nascimento, valor_renda, valor_parcela, prazo = 36)
  begin
    token = get_token
    return nil unless token
    
    url = "#{API_BASE}/proposta/operacoes-disponiveis"
    params = {
      produto: 'D',
      tipo_operacao: 13,
      averbador: 10010,
      convenio: 3,
      opcao_valor: 2,  # 2 = parcela
      valor_parcela: valor_parcela,
      prazo: prazo,
      cpf: cpf,
      data_nascimento: data_nascimento,
      valor_renda: valor_renda
    }
    
    headers = {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json',
      'User-Agent' => 'RoboMaffezzolli/1.0'
    }
    
    puts "🔍 Consultando operações disponíveis para CPF #{cpf}..."
    puts "🔍 URL: #{url}"
    puts "🔍 Params: #{params}"
    
    response = HTTParty.get(url, query: params, headers: headers, timeout: 30)
    
    puts "📊 Status operações disponíveis: #{response.code}"
    puts "📊 Response operações disponíveis: #{response.body}"
    
    if response.success?
      data = JSON.parse(response.body)
      if data['erro'] == false && data['tabelas'] && !data['tabelas'].empty?
        # Pega a primeira tabela disponível (melhor opção)
        tabela = data['tabelas'][0]
        return {
          tabela: tabela['tabela'],
          codigo_tabela: tabela['codigoTabela'],
          taxa: tabela['taxa'],
          prazo: tabela['prazo'],
          contrato: tabela['contrato'],
          parcela: tabela['parcela'],
          coeficiente: tabela['coeficiente']
        }
      end
    end
    
    return nil
  rescue => e
    puts "❌ Erro na consulta de operações disponíveis: #{e.message}"
    return nil
  end
end

# Rota principal
get '/' do
  erb :index
end

# Rota para testar conexão
get '/api/test-connection' do
  content_type :json
  
  token = get_token
  
  if token
    {
      success: true,
      message: 'Conexão estabelecida com sucesso',
      token_available: true,
      timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
    }.to_json
  else
    status 401
    {
      success: false,
      message: 'Falha na autenticação com a API',
      token_available: false,
      timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
    }.to_json
  end
end

# Rota para simular um único CPF
post '/api/simulate-single' do
  content_type :json
  
  begin
    request_data = JSON.parse(request.body.read)
    cpf = request_data['cpf']
    
    if cpf.nil? || cpf.empty?
      status 400
      return { error: 'CPF não fornecido' }.to_json
    end
    
    # Processa apenas um CPF
    clean_cpf = cpf.gsub(/\D/, '').rjust(11, '0')
    puts "🔍 DEBUG CPF: '#{cpf}' → '#{clean_cpf}' (#{clean_cpf.length} dígitos)"
    
    if clean_cpf.length == 11
      result = consultar_cpf(clean_cpf)
      
      # Inicializa valores padrão
      valor_maximo_emprestimo = 'N/A'
      prazo_maximo = 'N/A'
      taxa_juros = 'N/A'
      tabela_operacao = 'N/A'
      
      # Calcula margem utilizável (69,90% da margem disponível)
      margem_utilizavel = 0
      if result[:raw_data] && result[:raw_data]['valorMargemDisponivel']
        margem_raw = result[:raw_data]['valorMargemDisponivel'].gsub(',', '.').to_f
        puts "🔍 DEBUG MARGEM - CPF #{clean_cpf}: margem_raw = #{result[:raw_data]['valorMargemDisponivel']}"
        puts "🔍 DEBUG MARGEM - CPF #{clean_cpf}: margem_total = #{margem_raw}"
        margem_utilizavel = margem_raw * 0.699
        puts "🔍 DEBUG MARGEM - CPF #{clean_cpf}: margem_utilizavel = #{margem_utilizavel}"
      end
      
      # Se o CPF é elegível, faz consultas adicionais
      puts "🔍 DEBUG: Verificando elegibilidade para #{clean_cpf}"
      puts "🔍 DEBUG: result[:raw_data] = #{result[:raw_data] ? 'presente' : 'ausente'}"
      if result[:raw_data]
        puts "🔍 DEBUG: elegivel = #{result[:raw_data]['elegivel']}"
      end
      
      if result[:raw_data] && result[:raw_data]['elegivel'] == 'SIM'
        puts "🔧 CONSULTANDO VALORES DINÂMICOS DA API para CPF #{clean_cpf}"
        
        # Extrai dados necessários para as consultas
        data_nascimento = result[:raw_data]['dataNascimento']
        valor_renda = result[:raw_data]['valorTotalVencimentos'].gsub(',', '.').to_f
        sexo_codigo = result[:raw_data]['sexo_codigo']
        
        # Converte código de sexo para formato da API
        sexo = case sexo_codigo
               when '1' then 'M'
               when '2' then 'F'
               else 'M' # padrão
               end
        
        # Calcula tempo de empresa (assumindo data de admissão)
        if result[:raw_data]['dataAdmissao'] && !result[:raw_data]['dataAdmissao'].empty?
          data_admissao = Date.strptime(result[:raw_data]['dataAdmissao'], '%d/%m/%Y')
          tempo_empresa = ((Date.today - data_admissao) / 30).to_i # meses
        else
          tempo_empresa = 12 # padrão se não tiver data
        end
        
        puts "🔍 Dados extraídos - data_nascimento: #{data_nascimento}, valor_renda: #{valor_renda}, sexo_codigo: #{sexo_codigo} → sexo: #{sexo}"
        puts "🔍 tempo_empresa calculado: #{tempo_empresa} meses"
        
        # 1. Consulta política de crédito (limites máximos)
        politica = consultar_politica_credito(clean_cpf, data_nascimento, tempo_empresa, valor_renda, sexo)
        puts "🔍 Política de crédito para #{clean_cpf}: #{politica}"
        
        # 2. Calcula margem utilizável (69,90% da margem disponível)
        margem_utilizavel_valor = margem_utilizavel
        puts "🔍 Margem utilizável para #{clean_cpf}: #{margem_utilizavel_valor}"
        
        # 3. Consulta operações disponíveis
        operacoes = consultar_operacoes_disponiveis(clean_cpf, data_nascimento, valor_renda, margem_utilizavel_valor)
        puts "🔍 Operações disponíveis para #{clean_cpf}: #{operacoes}"
        
        # 4. Aplica lógica de priorização
        if operacoes && politica
          puts "🔍 Comparação #{clean_cpf}: Política=R$#{politica[:valor_maximo]}/#{politica[:prazo_maximo]}m vs Operações=R$#{operacoes[:contrato]}/#{operacoes[:prazo]}m"
          
          # Se operações excedem limites da política, ajusta
          if operacoes[:contrato].to_f > politica[:valor_maximo].to_f || operacoes[:prazo].to_i > politica[:prazo_maximo].to_i
            puts "⚠️ Valor/prazo excede política para #{clean_cpf}, ajustando..."
            
            # Recalcula com limites da política
            nova_parcela = politica[:valor_maximo].to_f / politica[:prazo_maximo].to_i
            puts "🔍 Nova parcela calculada para #{clean_cpf}: R$ #{nova_parcela.round(2)}"
            
            operacoes_ajustadas = consultar_operacoes_disponiveis(clean_cpf, data_nascimento, valor_renda, nova_parcela, politica[:prazo_maximo].to_i)
            puts "🔍 Operações ajustadas para #{clean_cpf}: #{operacoes_ajustadas}"
            
            if operacoes_ajustadas
              valor_maximo_emprestimo = "R$ #{politica[:valor_maximo]}"
              prazo_maximo = "#{politica[:prazo_maximo]} meses"
              taxa_juros = "#{operacoes_ajustadas[:taxa]}%"
              tabela_operacao = operacoes_ajustadas[:tabela]
              puts "✅ Usando operações ajustadas para #{clean_cpf}"
            else
              # Fallback para política
              valor_maximo_emprestimo = "R$ #{politica[:valor_maximo]}"
              prazo_maximo = "#{politica[:prazo_maximo]} meses"
              puts "✅ Usando política para #{clean_cpf}"
            end
          else
            # Usa operações disponíveis
            valor_maximo_emprestimo = "R$ #{operacoes[:contrato]}"
            prazo_maximo = "#{operacoes[:prazo]} meses"
            taxa_juros = "#{operacoes[:taxa]}%"
            tabela_operacao = operacoes[:tabela]
            puts "✅ Usando operações para #{clean_cpf}"
          end
        elsif operacoes
          # Só tem operações
          valor_maximo_emprestimo = "R$ #{operacoes[:contrato]}"
          prazo_maximo = "#{operacoes[:prazo]} meses"
          taxa_juros = "#{operacoes[:taxa]}%"
          tabela_operacao = operacoes[:tabela]
          puts "✅ Usando apenas operações para #{clean_cpf}"
        elsif politica
          # Só tem política
          valor_maximo_emprestimo = "R$ #{politica[:valor_maximo]}"
          prazo_maximo = "#{politica[:prazo_maximo]} meses"
          puts "✅ Usando apenas política para #{clean_cpf}"
        else
          puts "❌ Nenhuma consulta retornou dados para #{clean_cpf}"
        end
        
        puts "🎯 Resultado final para #{clean_cpf}: #{valor_maximo_emprestimo}, #{prazo_maximo}, #{taxa_juros}"
      end
      
      formatted_result = {
        cpf: clean_cpf,
        status: result[:erro] ? 'Erro' : 'Sucesso',
        nome: result[:raw_data] ? result[:raw_data]['nome'] : result[:mensagem],
        renda: result[:raw_data] ? "R$ #{result[:raw_data]['valorTotalVencimentos']}" : 'N/A',
        margem: result[:raw_data] ? "R$ #{result[:raw_data]['valorMargemDisponivel']}" : 'N/A',
        elegivel: result[:raw_data] ? (result[:raw_data]['elegivel'] == 'SIM' ? 'Sim' : 'Nao') : 'N/A',
        data_nascimento: result[:raw_data] ? result[:raw_data]['dataNascimento'] : 'N/A',
        matricula: result[:raw_data] ? result[:raw_data]['matricula'] : 'N/A',
        empregador: result[:raw_data] ? result[:raw_data]['nomeEmpregador'] : 'N/A',
        valor_maximo_emprestimo: valor_maximo_emprestimo,
        prazo_maximo: prazo_maximo,
        valor_contrato_maximo: margem_utilizavel > 0 ? "R$ #{margem_utilizavel.round(2)}" : 'N/A',  # 69,90% da margem
        taxa_juros: taxa_juros,
        tabela_operacao: tabela_operacao,
        raw_data: result[:raw_data]
      }
      
      # Salva dados no cache global para exportação
      $simulation_data << {
        cpf: clean_cpf,
        nome: formatted_result[:nome],
        status: formatted_result[:status],
        data_nascimento: formatted_result[:data_nascimento],
        sexo: result[:raw_data] ? result[:raw_data]['sexo_descricao'] : 'N/A',
        matricula: formatted_result[:matricula],
        renda: formatted_result[:renda],
        base_margem: result[:raw_data] ? "R$ #{result[:raw_data]['valorBaseMargem']}" : 'N/A',
        margem_disponivel: formatted_result[:margem],
        elegivel: formatted_result[:elegivel],
        data_admissao: result[:raw_data] ? result[:raw_data]['dataAdmissao'] : 'N/A',
        data_desligamento: result[:raw_data] ? result[:raw_data]['dataDesligamento'] : 'N/A',
        empregador: formatted_result[:empregador],
        cnpj_empregador: result[:raw_data] ? result[:raw_data]['numeroInscricaoEmpregador'] : 'N/A',
        tipo_inscricao: result[:raw_data] ? result[:raw_data]['inscricaoEmpregador_descricao'] : 'N/A',
        cnae_descricao: result[:raw_data] ? result[:raw_data]['cnae_descricao'] : 'N/A',
        data_inicio_atividade_empregador: result[:raw_data] ? result[:raw_data]['dataInicioAtividadeEmpregador'] : 'N/A',
        nome_mae: result[:raw_data] ? result[:raw_data]['nomeMae'] : 'N/A',
        nacionalidade: result[:raw_data] ? result[:raw_data]['paisNacionalidade_descricao'] : 'N/A',
        cbo_descricao: result[:raw_data] ? result[:raw_data]['cbo_descricao'] : 'N/A',
        codigo_categoria: result[:raw_data] ? result[:raw_data]['codigoCategoriaTrabalhador'] : 'N/A',
        pessoa_exposta_politicamente: result[:raw_data] ? result[:raw_data]['pessoaExpostaPoliticamente_descricao'] : 'N/A',
        possui_alertas: result[:raw_data] ? result[:raw_data]['possuiAlertas'] : 'N/A',
        qtd_emprestimos_ativos: result[:raw_data] ? result[:raw_data]['qtdEmprestimosAtivosSuspensos'] : 'N/A',
        emprestimos_legados: result[:raw_data] ? result[:raw_data]['emprestimosLegados'] : 'N/A',
        motivo_inelegibilidade: result[:raw_data] ? result[:raw_data]['motivoInelegibilidade_descricao'] : 'N/A',
        erro_codigo: result[:raw_data] ? result[:raw_data]['erro_codigo'] : 'N/A',
        erro_mensagem: result[:raw_data] ? result[:raw_data]['erro_mensagem'] : 'N/A',
        status_code: result[:raw_data] ? result[:raw_data]['status_code'] : 'N/A',
        valor_maximo_emprestimo: valor_maximo_emprestimo,
        prazo_maximo: prazo_maximo,
        valor_contrato_maximo: formatted_result[:valor_contrato_maximo],
        taxa_juros: taxa_juros,
        tabela_operacao: tabela_operacao,
        timestamp: Time.now.strftime('%d/%m/%Y %H:%M')
      }
      
      return {
        success: true,
        result: formatted_result,
        timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
      }.to_json
    else
      return {
        success: false,
        error: 'CPF deve ter 11 dígitos',
        cpf: cpf,
        timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
      }.to_json
    end
    
  rescue => e
    puts "❌ Erro na simulação individual: #{e.message}"
    puts e.backtrace
    status 500
    return {
      success: false,
      error: e.message,
      timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
    }.to_json
  end
end

# Rota para simular CPFs (mantida para compatibilidade)
post '/api/simulate' do
  content_type :json
  
  # Limpa cache de dados anteriores
  $simulation_data = []
  puts "🔄 Cache de simulação limpo"
  
  begin
    
    request_data = JSON.parse(request.body.read)
    cpfs = request_data['cpfs'] || []
    
    if cpfs.empty?
      status 400
      return { error: 'Nenhum CPF fornecido' }.to_json
    end
    
    results = []
    
    cpfs.each do |cpf|
      # Limpa CPF (remove caracteres não numéricos) e adiciona zeros à esquerda se necessário
      clean_cpf = cpf.gsub(/\D/, '').rjust(11, '0')
      puts "🔍 DEBUG CPF: '#{cpf}' → '#{clean_cpf}' (#{clean_cpf.length} dígitos)"
      
      if clean_cpf.length == 11
        result = consultar_cpf(clean_cpf)
        
        # Formata resultado para exibição
        margem_raw = result[:raw_data] ? result[:raw_data]['valorMargemDisponivel'] : nil
        puts "🔍 DEBUG MARGEM - CPF #{clean_cpf}: margem_raw = #{margem_raw}"
        margem_total = margem_raw ? margem_raw.gsub(',', '.').to_f : 0  # Converte vírgula para ponto
        puts "🔍 DEBUG MARGEM - CPF #{clean_cpf}: margem_total = #{margem_total}"
        margem_utilizavel = margem_total * 0.699  # 69,90% da margem disponível
        puts "🔍 DEBUG MARGEM - CPF #{clean_cpf}: margem_utilizavel = #{margem_utilizavel}"
        
        # Inicializa valores padrão
        valor_maximo_emprestimo = 'N/A'
        prazo_maximo = 'N/A'
        taxa_juros = 'N/A'
        tabela_operacao = 'N/A'
        
        # Se o CPF é elegível, faz consultas adicionais
        puts "🔍 DEBUG: Verificando elegibilidade para #{clean_cpf}"
        puts "🔍 DEBUG: result[:raw_data] = #{result[:raw_data] ? 'presente' : 'ausente'}"
        if result[:raw_data]
          puts "🔍 DEBUG: elegivel = #{result[:raw_data]['elegivel']}"
        end
        
        if result[:raw_data] && result[:raw_data]['elegivel'] == 'SIM'
          puts "🔧 CONSULTANDO VALORES DINÂMICOS DA API para CPF #{clean_cpf}"
          
          # Extrai dados necessários para as consultas
          data_nascimento = result[:raw_data]['dataNascimento']
          valor_renda = result[:raw_data]['valorTotalVencimentos'].gsub(',', '.').to_f
          sexo_codigo = result[:raw_data]['sexo_codigo']
          
          # Converte código de sexo para formato da API
          sexo = case sexo_codigo
                 when '1' then 'M'
                 when '2' then 'F'
                 else 'M' # padrão
                 end
          
          # Calcula tempo de empresa (assumindo data de admissão)
          if result[:raw_data]['dataAdmissao'] && !result[:raw_data]['dataAdmissao'].empty?
            data_admissao = Date.strptime(result[:raw_data]['dataAdmissao'], '%d/%m/%Y')
            tempo_empresa = ((Date.today - data_admissao) / 30).to_i # meses
          else
            tempo_empresa = 12 # padrão se não tiver data
          end
          
          puts "🔍 Dados extraídos - data_nascimento: #{data_nascimento}, valor_renda: #{valor_renda}, sexo_codigo: #{sexo_codigo} → sexo: #{sexo}"
          puts "🔍 tempo_empresa calculado: #{tempo_empresa} meses"
          
          # 1. Consulta política de crédito (limites máximos)
          politica = consultar_politica_credito(clean_cpf, data_nascimento, tempo_empresa, valor_renda, sexo)
          puts "🔍 Política de crédito para #{clean_cpf}: #{politica}"
          
          # 2. Calcula margem utilizável (69,90% da margem disponível)
          margem_utilizavel_valor = margem_utilizavel
          puts "🔍 Margem utilizável para #{clean_cpf}: #{margem_utilizavel_valor}"
          
          # 3. Consulta operações disponíveis
          operacoes = consultar_operacoes_disponiveis(clean_cpf, data_nascimento, valor_renda, margem_utilizavel_valor)
          puts "🔍 Operações disponíveis para #{clean_cpf}: #{operacoes}"
          
          # 4. Aplica lógica de priorização
          if operacoes && politica
            puts "🔍 Comparação #{clean_cpf}: Política=R$#{politica[:valor_maximo]}/#{politica[:prazo_maximo]}m vs Operações=R$#{operacoes[:contrato]}/#{operacoes[:prazo]}m"
            
            # Se operações excedem limites da política, ajusta
            if operacoes[:contrato].to_f > politica[:valor_maximo].to_f || operacoes[:prazo].to_i > politica[:prazo_maximo].to_i
              puts "⚠️ Valor/prazo excede política para #{clean_cpf}, ajustando..."
              
              # Recalcula com limites da política
              nova_parcela = politica[:valor_maximo].to_f / politica[:prazo_maximo].to_i
              puts "🔍 Nova parcela calculada para #{clean_cpf}: R$ #{nova_parcela.round(2)}"
              
              operacoes_ajustadas = consultar_operacoes_disponiveis(clean_cpf, data_nascimento, valor_renda, nova_parcela, politica[:prazo_maximo].to_i)
              puts "🔍 Operações ajustadas para #{clean_cpf}: #{operacoes_ajustadas}"
              
              if operacoes_ajustadas
                valor_maximo_emprestimo = "R$ #{politica[:valor_maximo]}"
                prazo_maximo = "#{politica[:prazo_maximo]} meses"
                taxa_juros = "#{operacoes_ajustadas[:taxa]}%"
                tabela_operacao = operacoes_ajustadas[:tabela]
                puts "✅ Usando operações ajustadas para #{clean_cpf}"
              else
                # Fallback para política
                valor_maximo_emprestimo = "R$ #{politica[:valor_maximo]}"
                prazo_maximo = "#{politica[:prazo_maximo]} meses"
                puts "✅ Usando política para #{clean_cpf}"
              end
            else
              # Usa operações disponíveis
              valor_maximo_emprestimo = "R$ #{operacoes[:contrato]}"
              prazo_maximo = "#{operacoes[:prazo]} meses"
              taxa_juros = "#{operacoes[:taxa]}%"
              tabela_operacao = operacoes[:tabela]
              puts "✅ Usando operações para #{clean_cpf}"
            end
          elsif operacoes
            # Só tem operações
            valor_maximo_emprestimo = "R$ #{operacoes[:contrato]}"
            prazo_maximo = "#{operacoes[:prazo]} meses"
            taxa_juros = "#{operacoes[:taxa]}%"
            tabela_operacao = operacoes[:tabela]
            puts "✅ Usando apenas operações para #{clean_cpf}"
          elsif politica
            # Só tem política
            valor_maximo_emprestimo = "R$ #{politica[:valor_maximo]}"
            prazo_maximo = "#{politica[:prazo_maximo]} meses"
            puts "✅ Usando apenas política para #{clean_cpf}"
          else
            puts "❌ Nenhuma consulta retornou dados para #{clean_cpf}"
          end
          
          puts "🎯 Resultado final para #{clean_cpf}: #{valor_maximo_emprestimo}, #{prazo_maximo}, #{taxa_juros}"
        end
        
        formatted_result = {
          cpf: clean_cpf,
          status: result[:erro] ? 'Erro' : 'Sucesso',
          nome: result[:raw_data] ? result[:raw_data]['nome'] : result[:mensagem],
          renda: result[:raw_data] ? "R$ #{result[:raw_data]['valorTotalVencimentos']}" : 'N/A',
          margem: result[:raw_data] ? "R$ #{result[:raw_data]['valorMargemDisponivel']}" : 'N/A',
          elegivel: result[:raw_data] ? (result[:raw_data]['elegivel'] == 'SIM' ? 'Sim' : 'Nao') : 'N/A',
          data_nascimento: result[:raw_data] ? result[:raw_data]['dataNascimento'] : 'N/A',
          matricula: result[:raw_data] ? result[:raw_data]['matricula'] : 'N/A',
          empregador: result[:raw_data] ? result[:raw_data]['nomeEmpregador'] : 'N/A',
          valor_maximo_emprestimo: valor_maximo_emprestimo,
          prazo_maximo: prazo_maximo,
          valor_contrato_maximo: margem_utilizavel > 0 ? "R$ #{margem_utilizavel.round(2)}" : 'N/A',  # 69,90% da margem
          taxa_juros: taxa_juros,
          tabela_operacao: tabela_operacao,
          raw_data: result[:raw_data]
        }
        
        # Salva dados no cache global para exportação
        $simulation_data << {
          cpf: clean_cpf,
          nome: formatted_result[:nome],
          status: formatted_result[:status],
          data_nascimento: formatted_result[:data_nascimento],
          sexo: result[:raw_data] ? result[:raw_data]['sexo_descricao'] : 'N/A',
          matricula: formatted_result[:matricula],
          renda: formatted_result[:renda],
          base_margem: result[:raw_data] ? "R$ #{result[:raw_data]['valorBaseMargem']}" : 'N/A',
          margem: formatted_result[:margem],
          elegivel: formatted_result[:elegivel],
          data_admissao: result[:raw_data] ? result[:raw_data]['dataAdmissao'] : 'N/A',
          data_desligamento: result[:raw_data] ? result[:raw_data]['dataDesligamento'] : 'N/A',
          empregador: formatted_result[:empregador],
          cnpj_empregador: result[:raw_data] ? result[:raw_data]['numeroInscricaoEmpregador'] : 'N/A',
          tipo_inscricao: result[:raw_data] ? result[:raw_data]['inscricaoEmpregador_descricao'] : 'N/A',
          cnae_descricao: result[:raw_data] ? result[:raw_data]['cnae_descricao'] : 'N/A',
          data_inicio_atividade: result[:raw_data] ? result[:raw_data]['dataInicioAtividadeEmpregador'] : 'N/A',
          nome_mae: result[:raw_data] ? result[:raw_data]['nomeMae'] : 'N/A',
          nacionalidade: result[:raw_data] ? result[:raw_data]['paisNacionalidade_descricao'] : 'N/A',
          cbo_descricao: result[:raw_data] ? result[:raw_data]['cbo_descricao'] : 'N/A',
          codigo_categoria: result[:raw_data] ? result[:raw_data]['codigoCategoriaTrabalhador'] : 'N/A',
          pessoa_exposta: result[:raw_data] ? result[:raw_data]['pessoaExpostaPoliticamente_descricao'] : 'N/A',
          possui_alertas: result[:raw_data] ? result[:raw_data]['possuiAlertas'] : 'N/A',
          qtd_emprestimos: result[:raw_data] ? result[:raw_data]['qtdEmprestimosAtivosSuspensos'] : 'N/A',
          emprestimos_legados: result[:raw_data] ? result[:raw_data]['emprestimosLegados'] : 'N/A',
          motivo_inelegibilidade: result[:raw_data] ? result[:raw_data]['motivoInelegibilidade_descricao'] : 'N/A',
          erro_codigo: result[:raw_data] ? result[:raw_data]['erro_codigo'] : 'N/A',
          erro_mensagem: result[:raw_data] ? result[:raw_data]['erro_mensagem'] : 'N/A',
          status_code: result[:raw_data] ? result[:raw_data]['status_code'] : 'N/A',
          valor_maximo_emprestimo: formatted_result[:valor_maximo_emprestimo],
          prazo_maximo: formatted_result[:prazo_maximo],
          valor_contrato_maximo: formatted_result[:valor_contrato_maximo],
          taxa_juros: formatted_result[:taxa_juros],
          tabela_operacao: formatted_result[:tabela_operacao]
        }
        
        results << formatted_result
      else
        results << {
          cpf: cpf,
          status: 'Erro',
          nome: 'CPF inválido',
          error: 'CPF deve ter 11 dígitos'
        }
      end
    end
    
    {
      success: true,
      results: results,
      total: results.length,
      timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
    }.to_json
    
  rescue => e
    puts "❌ Erro na simulação: #{e.message}"
    status 500
    {
      success: false,
      error: e.message,
      timestamp: Time.now.strftime('%d/%m/%Y %H:%M:%S')
    }.to_json
  end
end

# Rota para exportar CSV
get '/api/export-csv' do
  content_type 'text/csv'
  attachment 'simulacao_maffezzolli.csv'
  
  # Dados de exemplo (em produção, viria do banco de dados)
  csv_data = CSV.generate(headers: true) do |csv|
    csv << ['CPF', 'Nome', 'Status', 'Renda', 'Margem', 'Elegível', 'Data Nascimento', 'Matrícula', 'Empregador']
    csv << ['81358237115', 'Exemplo', 'Sucesso', 'R$ 5.000,00', 'R$ 1.500,00', 'Sim', '01/01/1980', '12345', 'Empresa XYZ']
  end
  
  csv_data
end

# Inicialização
if __FILE__ == $0
  puts "🚀 Iniciando Robô Maffezzolli CLT Facta (Ruby/Sinatra)..."
  puts "🌐 Servidor rodando em http://0.0.0.0:4567"
  puts "📋 Credenciais configuradas: #{CREDENTIALS[:login]}"
end



# Cache global para dados da simulação
$simulation_data = []

# Rota para exportar Excel
get '/api/export-excel' do
  content_type 'text/csv; charset=utf-8'
  
  # Nome do arquivo com timestamp
  timestamp = Time.now.strftime('%d-%mh%H-%M')
  attachment "Resultado#{timestamp}.csv"
  
  # Headers da planilha (sem acentos para evitar problemas)
  headers = [
    'CPF', 'Nome', 'Status', 'Data Nascimento', 'Sexo', 'Matricula',
    'Renda Mensal', 'Base Margem', 'Margem Disponivel', 'Elegivel',
    'Data Admissao', 'Data Desligamento', 'Empregador', 'CNPJ Empregador',
    'Tipo Inscricao', 'CNAE Descricao', 'Data Inicio Atividade Empregador',
    'Nome Mae', 'Nacionalidade', 'CBO Descricao', 'Codigo Categoria',
    'Pessoa Exposta Politicamente', 'Possui Alertas', 'Qtd Emprestimos Ativos',
    'Emprestimos Legados', 'Motivo Inelegibilidade', 'Erro Codigo',
    'Erro Mensagem', 'Status Code', 'Valor Maximo Emprestimo', 'Prazo Maximo',
    'Valor Contrato Maximo', 'Taxa Juros', 'Tabela Operacao', 'Timestamp'
  ]
  
  # Gera CSV com dados da simulação
  csv_data = CSV.generate(col_sep: ';', headers: true) do |csv|
    csv << headers
    
    if $simulation_data && !$simulation_data.empty?
      $simulation_data.each do |item|
        csv << [
          item[:cpf] || 'N/A',
          item[:nome] || 'N/A',
          item[:status] || 'N/A',
          item[:data_nascimento] || 'N/A',
          item[:sexo] || 'N/A',
          item[:matricula] || 'N/A',
          item[:renda] || 'N/A',
          item[:base_margem] || 'N/A',
          item[:margem] || 'N/A',
          item[:elegivel] || 'N/A',
          item[:data_admissao] || 'N/A',
          item[:data_desligamento] || 'N/A',
          item[:empregador] || 'N/A',
          item[:cnpj_empregador] || 'N/A',
          item[:tipo_inscricao] || 'N/A',
          item[:cnae_descricao] || 'N/A',
          item[:data_inicio_atividade] || 'N/A',
          item[:nome_mae] || 'N/A',
          item[:nacionalidade] || 'N/A',
          item[:cbo_descricao] || 'N/A',
          item[:codigo_categoria] || 'N/A',
          item[:pessoa_exposta] || 'N/A',
          item[:possui_alertas] || 'N/A',
          item[:qtd_emprestimos] || 'N/A',
          item[:emprestimos_legados] || 'N/A',
          item[:motivo_inelegibilidade] || 'N/A',
          item[:erro_codigo] || 'N/A',
          item[:erro_mensagem] || 'N/A',
          item[:status_code] || 'N/A',
          item[:valor_maximo_emprestimo] || 'N/A',
          item[:prazo_maximo] || 'N/A',
          item[:valor_contrato_maximo] || 'N/A',
          item[:taxa_juros] || 'N/A',
          item[:tabela_operacao] || 'N/A',
          Time.now.strftime('%d/%m/%Y %H:%M:%S')
        ]
      end
    else
      # Se não há dados, adiciona linha vazia
      csv << Array.new(headers.length, 'N/A')
    end
  end
  
  csv_data
end

