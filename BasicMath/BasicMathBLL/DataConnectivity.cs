
using System.Collections.Generic;

using System.Data.SqlClient;
using System.Configuration;

namespace BasicMath.BasicMathBLL
{
	public class DataConnectivity : Program
	{		
		List<int> values = new List<int>();
	
		public List<int> GetData()
		{
			
			string connection = ConfigurationManager.ConnectionStrings["MyDbConnection"].ConnectionString;
			using (SqlConnection conn = new SqlConnection(connection))
			{
				conn.Open();
				using (SqlCommand cmd = new SqlCommand("SELECT * FROM basicMath", conn))
				{
					using (SqlDataReader reader = cmd.ExecuteReader())
					{
						while (reader.Read())
						{
							int v1=reader.GetInt32(0);
							int v2=reader.GetInt32(1);
							values.Add(v1);
							values.Add(v2);							
						}
						reader.Close();
					}
				}
			}
			return values;
		}




	}
}
