using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using BasicMath;
using BasicMath.BasicMathBLL;
using System.Collections.Generic;

namespace BasicMathTest
{
	[TestClass]
	public class UnitTest1
	{
       public DataConnectivity data = new DataConnectivity();
		public List<int> val = new List<int>();

        [TestMethod]
		public void Test_AddMethod()
		{		
			BasicMaths bm = new BasicMaths();
			val = data.GetData();
			double res = bm.Add(val[0], val[1]);
			Assert.AreEqual(res, 35);
		}
		[TestMethod]
		public void Test_SubstractMethod()
		{
			BasicMaths bm = new BasicMaths();
            val = data.GetData();
            double res = bm.Substract(val[0], val[1]);
			Assert.AreEqual(res, 5);
		}
		[TestMethod]
		public void Test_DivideMethod()
		{
			BasicMaths bm = new BasicMaths();
            val = data.GetData();
            double res = Math.Round(bm.divide(val[0], val[1]),2);
			Assert.AreEqual(res, 1.33);
		}
		[TestMethod]
		public void Test_MultiplyMethod()
		{
			BasicMaths bm = new BasicMaths();
            val = data.GetData();
            double res = bm.Multiply(val[0], val[1]);
			Assert.AreEqual(res, 300);
		}
	}
}
