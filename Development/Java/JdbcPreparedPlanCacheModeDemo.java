import java.sql.*;
import java.util.Properties;

public class JdbcPreparedPlanCacheModeDemo {
    public static void main(String[] args) {

        SetupTableData(GetConnectDefault());

        ExecutePrepareStatements(GetConnectPrepareThreshold5CacheModeAuto());
        ExecutePrepareStatements(GetConnectPrepareThreshold5CacheModeForceCustom());
        ExecutePrepareStatements(GetConnectPrepareThreshold5CacheModeForceGeneric());
        ExecutePrepareStatements(GetConnectPrepareThreshold10CacheModeAuto());
        ExecutePrepareStatements(GetConnectPrepareThreshold10CacheModeForceCustom());
        ExecutePrepareStatements(GetConnectPrepareThreshold10CacheModeForceGeneric());        
        ExecutePrepareStatements(GetConnectPrepareThreshold1CacheModeAuto());
        ExecutePrepareStatements(GetConnectPrepareThreshold1CacheModeForceCustom());
        ExecutePrepareStatements(GetConnectPrepareThreshold1CacheModeForceGeneric());

        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold5CacheModeAuto());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold5CacheModeForceCustom());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold5CacheModeForceGeneric());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold10CacheModeAuto());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold10CacheModeForceCustom());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold10CacheModeForceGeneric());        
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold1CacheModeAuto());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold1CacheModeForceCustom());
        ExecutePrepareStatementsStart1000(GetConnectPrepareThreshold1CacheModeForceGeneric());

        ExecuteStatements(GetConnectPrepareThreshold5CacheModeAuto());
        ExecuteStatements(GetConnectPrepareThreshold5CacheModeForceCustom());
        ExecuteStatements(GetConnectPrepareThreshold5CacheModeForceGeneric());
        ExecuteStatements(GetConnectPrepareThreshold10CacheModeAuto());
        ExecuteStatements(GetConnectPrepareThreshold10CacheModeForceCustom());
        ExecuteStatements(GetConnectPrepareThreshold10CacheModeForceGeneric());        
        ExecuteStatements(GetConnectPrepareThreshold1CacheModeAuto());
        ExecuteStatements(GetConnectPrepareThreshold1CacheModeForceCustom());
        ExecuteStatements(GetConnectPrepareThreshold1CacheModeForceGeneric());        

        ExecuteStatementsStart1000(GetConnectPrepareThreshold5CacheModeAuto());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold5CacheModeForceCustom());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold5CacheModeForceGeneric());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold10CacheModeAuto());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold10CacheModeForceCustom());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold10CacheModeForceGeneric());        
        ExecuteStatementsStart1000(GetConnectPrepareThreshold1CacheModeAuto());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold1CacheModeForceCustom());
        ExecuteStatementsStart1000(GetConnectPrepareThreshold1CacheModeForceGeneric());         

        CleanTableData(GetConnectDefault());

    }

    static Connection GetConnectDefault() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
         props.setProperty("ApplicationName", "DefaultJDBCConnection");
        props.setProperty("options", "-c log_statement=all");
    
        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: DefaultJDBCConnection");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold5CacheModeAuto() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeAuto");
        props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "5");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold5CacheModeAuto");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold5CacheModeForceCustom() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceCustom");
        props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "5");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold5CacheModeForceCustom");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold5CacheModeForceGeneric() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceGeneric");
        props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "5");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold5CacheModeForceGeneric");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

   static Connection GetConnectPrepareThreshold10CacheModeAuto() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeAuto");
        props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "10");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold10CacheModeAuto");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold10CacheModeForceCustom() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceCustom");
        props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "10");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold10CacheModeForceCustom");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold10CacheModeForceGeneric() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceGeneric");
        props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "10");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold10CacheModeForceGeneric");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }    

    static Connection GetConnectPrepareThreshold1CacheModeAuto() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeAuto");
        props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "1");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold1CacheModeAuto");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold1CacheModeForceCustom() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceCustom");
        props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "1");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold1CacheModeForceCustom");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static Connection GetConnectPrepareThreshold1CacheModeForceGeneric() {
        String url = "jdbc:postgresql://postgres-instance1.abcdefg123456.us-east-1.rds.amazonaws.com/mytest";
        Properties props = new Properties();
        props.setProperty("user", "postgres");
        props.setProperty("password", "YourComplexPassword");
        props.setProperty("ssl", "false");
        props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceGeneric");
        props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
        props.setProperty("prepareThreshold", "1");

        Connection conn = null;

        try {
            conn = DriverManager.getConnection(url, props);
            System.out.println("Connected to the PostgreSQL server successfully: PrepareThreshold1CacheModeForceGeneric");
        } catch (SQLException e) {
            System.out.println(e.getMessage());
        }

        return conn;
    }

    static void SetupTableData(Connection conn) {
        
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("CREATE TABLE t (id INT, c TEXT)");    
            stmt.execute("INSERT INTO t SELECT CASE WHEN x<=10 THEN x ELSE 1000 END, RPAD('x',100,'x') FROM generate_series(1,1000) x");
            stmt.execute("CREATE INDEX t_id_n1 ON t (id)");
            stmt.close();
            conn.close();
        } catch (SQLException ex) {
            System.out.println(ex.getMessage());
        }    
    }

    static void CleanTableData(Connection conn) {
        
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("DROP TABLE t");
            stmt.close();
            conn.close(); 
        } catch (SQLException ex) {
            System.out.println(ex.getMessage());
        }    
    }    

    static void ExecutePrepareStatements(Connection conn) {
        
        try {
            PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");

            ps.setInt(1, 1);
            ps.executeQuery().close();
            ps.setInt(1, 2);
            ps.executeQuery().close();
            ps.setInt(1, 3);
            ps.executeQuery().close();
            ps.setInt(1, 4);
            ps.executeQuery().close();
            ps.setInt(1, 5);
            ps.executeQuery().close();
            ps.setInt(1, 6);
            ps.executeQuery().close();
            ps.setInt(1, 1000);
            ps.executeQuery().close();
            ps.setInt(1, 7);
            ps.executeQuery().close();
            ps.setInt(1, 1000);
            ps.executeQuery().close(); 
            ps.close();
            conn.close();

        } catch (SQLException ex) {
            System.out.println(ex.getMessage());
        }    
    }   

    static void ExecutePrepareStatementsStart1000(Connection conn) {
        
        try {
            PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");

            ps.setInt(1, 1000);
            ps.executeQuery().close();
            ps.setInt(1, 2);
            ps.executeQuery().close();
            ps.setInt(1, 3);
            ps.executeQuery().close();
            ps.setInt(1, 4);
            ps.executeQuery().close();
            ps.setInt(1, 5);
            ps.executeQuery().close();
            ps.setInt(1, 6);
            ps.executeQuery().close();
            ps.setInt(1, 1000);
            ps.executeQuery().close();
            ps.setInt(1, 7);
            ps.executeQuery().close();
            ps.setInt(1, 1000);
            ps.executeQuery().close(); 
            
            ps.close();
            conn.close();

        } catch (SQLException ex) {
            System.out.println(ex.getMessage());
        }    
    }   

   static void ExecuteStatements(Connection conn) {
        
        try {

            Statement stmt = conn.createStatement();
            stmt.execute("SELECT * FROM t WHERE id = 1");  
            stmt.execute("SELECT * FROM t WHERE id = 2");  
            stmt.execute("SELECT * FROM t WHERE id = 3");
            stmt.execute("SELECT * FROM t WHERE id = 4");
            stmt.execute("SELECT * FROM t WHERE id = 5");
            stmt.execute("SELECT * FROM t WHERE id = 6");
            stmt.execute("SELECT * FROM t WHERE id = 1000");
            stmt.execute("SELECT * FROM t WHERE id = 7");
            stmt.execute("SELECT * FROM t WHERE id = 1000");
            stmt.close();
            conn.close();

        } catch (SQLException ex) {
            System.out.println(ex.getMessage());
        }    
    }

   static void ExecuteStatementsStart1000(Connection conn) {
        
        try {

            Statement stmt = conn.createStatement();
            stmt.execute("SELECT * FROM t WHERE id = 1000");  
            stmt.execute("SELECT * FROM t WHERE id = 2");  
            stmt.execute("SELECT * FROM t WHERE id = 3");
            stmt.execute("SELECT * FROM t WHERE id = 4");
            stmt.execute("SELECT * FROM t WHERE id = 5");
            stmt.execute("SELECT * FROM t WHERE id = 6");
            stmt.execute("SELECT * FROM t WHERE id = 7");
            stmt.execute("SELECT * FROM t WHERE id = 1000");
            stmt.close();
            conn.close();

        } catch (SQLException ex) {
            System.out.println(ex.getMessage());
        }    
    }   

}
