package agent;

@SuppressWarnings("unused")
public final class Common {

    public static final class AuthResponse {
        private int id;
        private String key;
        public static Builder newBuilder(){ return new Builder(); }
        public int getId(){ return id; }
        public String getKey(){ return key; }
        public static final class Builder{
            private final AuthResponse obj=new AuthResponse();
            public Builder setId(int i){ obj.id=i; return this; }
            public Builder setKey(String k){ obj.key=k; return this; }
            public AuthResponse build(){ return obj; }
        }
    }

    public static final class ListRequest {
        public static ListRequest getDefaultInstance(){ return new ListRequest(); }
    }
}
