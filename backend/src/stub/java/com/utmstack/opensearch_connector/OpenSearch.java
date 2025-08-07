package com.utmstack.opensearch_connector;

import com.utmstack.opensearch_connector.enums.*;
import com.utmstack.opensearch_connector.types.*;
import okhttp3.MediaType;
import okhttp3.Protocol;
import okhttp3.Request;
import okhttp3.Response;
import org.opensearch.client.opensearch._types.SortOrder;
import org.opensearch.client.opensearch.core.*;
import org.opensearch.client.opensearch._types.query_dsl.Query;

import java.io.IOException;
import java.util.*;

@SuppressWarnings("unused")
public class OpenSearch {

    /* ---------- builder -------------------------------------------------- */
    public static Builder builder() { return new Builder(); }
    public static final class Builder {
        public Builder withHost(String h, int p, HttpScheme s){ return this; }
        public OpenSearch build(){ return new OpenSearch(); }
    }

    /* ---------- cheap-but-useful helpers --------------------------------- */
    private static final Response OK_RESPONSE = new Response.Builder()
        .protocol(Protocol.HTTP_1_1)
        .request(new Request.Builder().url("http://localhost").build())
        .code(200).message("stub").body(okhttp3.ResponseBody.create("", MediaType.get("text/plain")))
        .build();

    /* ---------- methods actually used by UTMS code ----------------------- */
    public Map<String,Long> getFieldValues(String f, String i, Query q,
                                           Integer top, TermOrder o, SortOrder so){
        return Collections.emptyMap();
    }
    public boolean indexExist(String idx){ return false; }

    public <T> IndexResponse index(String idx, T doc){
        // a stub object – never accessed by UTMS
        return null;
    }

    public Map<String,String> getIndexProperties(String pattern){ return Collections.emptyMap(); }

    public List<org.opensearch.client.opensearch.cat.indices.IndicesRecord>
    getIndices(String pattern, IndexSort sort){ return List.of(); }

    public java.util.Optional<ElasticCluster> getClusterNodesInfo(){ return Optional.empty(); }

    public void deleteIndex(List<String> idx){ /* no-op */ }

    public <T> org.opensearch.client.opensearch.core.SearchResponse<T>
    search(org.opensearch.client.opensearch.core.SearchRequest r, Class<T> t){
        return null;
    }

    public <T> org.opensearch.client.opensearch.core.SearchResponse<T>
    search(org.opensearch.client.opensearch.core.SearchRequest r, java.lang.Class<T> t, Object... args){
        return null;
    }

    public void updateByQuery(Query q,String i,String s){ /* no-op */ }

    public okhttp3.Response executeHttpRequest(String uri, Map<String,String> p,
                                               Object body, HttpMethod m){
        // Many services only look at isSuccessful()/code()/body()==null
        return OK_RESPONSE;
    }
}
